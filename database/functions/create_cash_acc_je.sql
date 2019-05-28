/*************************************************************************
 *************************************************************************
 **
 ** File:         create_cash_acc_je.sql
 ** Project:      Muse Systems Cash Accounting for xTuple ERP
 ** Author:       Steven C. Buttgereit
 **
 ** (C) 2018 Lima Buttgereit Holdings LLC d/b/a Muse Systems
 **
 ** Contact:
 ** muse.information@musesystems.com  :: https://muse.systems
 **
 ** License: MIT License. See LICENSE.md for complete licensing details.
 **
 *************************************************************************
 ************************************************************************/

--
-- If a given yearperiod being closed is subject to cash accounting adjustments,
-- we create the necessary journal entries in this function.
--

CREATE OR REPLACE FUNCTION musecashacc.create_cash_acc_je(pYearPeriodId integer)
    RETURNS integer AS
        $BODY$
            DECLARE
                vIsCashAccEnabled boolean := musextputils.get_musemetric('musecashacc', 'isCashAccEnabled', null::boolean);
                vCashAccFirstYearPeriodId integer := musextputils.get_musemetric('musecashacc', 'cashAccFirstYearPeriodId', null::numeric)::integer;
                vArCashAdjAccntId integer;
                vRevCashAdjAccntId integer;
                vApCashAdjAccntId integer;
                vExpCashAdjAccntId integer;
                vGlSequence integer;

                vCashAdjDocNum text;

                vArOpenCurrentYearBal numeric := 0;
                vArOpenCurrentYearBalDocs text;
                vApOpenCurrentYearBal numeric := 0;
                vApOpenCurrentYearBalDocs text;
                vArOpenLastClosedCurrent numeric := 0;
                vArOpenLastClosedCurrentDocs text;
                vApOpenLastClosedCurrent numeric := 0;
                vApOpenLastClosedCurrentDocs text;

                vCurrentYearStart date;
                vCurrentYearEnd date;
            BEGIN

                -- Check if we do anything at all
                IF
                    NOT coalesce(vIsCashAccEnabled, false) OR
                    NOT coalesce(
                            (SELECT yearperiod_start FROM public.yearperiod WHERE yearperiod_id = pYearPeriodId) >=
                            (SELECT yearperiod_start FROM public.yearperiod WHERE yearperiod_id = vCashAccFirstYearPeriodId)
                            ,false)
                THEN
                    -- We've nothing to do
                    RETURN null::integer;

                END IF;

                -- We're on.  Get the remaining configs we'll need.
                vArCashAdjAccntId := musextputils.get_musemetric('musecashacc', 'arCashAdjAccntId', null::numeric)::integer;
                vRevCashAdjAccntId := musextputils.get_musemetric('musecashacc', 'revCashAdjAccntId', null::numeric)::integer;
                vApCashAdjAccntId := musextputils.get_musemetric('musecashacc', 'apCashAdjAccntId', null::numeric)::integer;
                vExpCashAdjAccntId := musextputils.get_musemetric('musecashacc', 'expCashAdjAccntId', null::numeric)::integer;

                vGlSequence := fetchGLSequence();

                -- Try to detect CR/CMs
                IF
                    EXISTS (SELECT true
                            FROM public.aropen
                                JOIN public.cashrcpt
                                    ON aropen_cust_id = cashrcpt_cust_id
                                        AND aropen_distdate = cashrcpt_distdate
                                        AND substring(aropen_notes,'^Unapplied from (.+)$') = (cashrcpt_fundstype || '-' || cashrcpt_docnumber)
                                        AND aropen_amount = cashrcpt_amount
                            WHERE aropen_open
                                AND aropen_doctype = 'C'
                                AND NOT cashrcpt_void)
                THEN
                    RAISE EXCEPTION
                    'We cannot properly process unapplied cash receipts which were created as Credit Memos.  These typically book to AR and we cannot tell them apart from customer credits granted for other reasons.  (FUNC: musecashacc.create_cash_acc_je) (pYearPeriodId: %)'
                    ,pYearPeriodId;

                END IF;

                -- Get our target doc num. and target years
                SELECT yearperiod_start, yearperiod_end
                INTO vCurrentYearStart, vCurrentYearEnd
                FROM public.yearperiod
                WHERE yearperiod_id = pYearPeriodId;

                SELECT
                    'CSHACC-'||
                        extract(year FROM vCurrentYearEnd)||'-'||
                        substring('000'||(coalesce((SELECT substring(gltrans_docnumber,'-([0-9]+)$')
                                    FROM gltrans
                                    WHERE gltrans_docnumber ~* ('^CSHACC-'||extract(year FROM vCurrentYearEnd))
                                    ORDER BY gltrans_docnumber DESC LIMIT 1)::integer,0)+1),'...$')
                INTO vCashAdjDocNum;

                -- Deal with Open AR opened this fiscal year
                SELECT
                     SUM(
                        CASE
                            WHEN aropen_doctype IN ('I', 'D') THEN
                                aropen_amount - aropen_paid
                            WHEN aropen_doctype IN ('C') THEN
                                (aropen_amount - aropen_paid) * -1
                            ELSE
                                0.00
                            END
                        )
                    ,E'\n\nDocument Details:\n---------------------------------------------\n'::text ||
                        string_agg(CASE
                                        WHEN
                                            aropen_doctype IN ('I', 'D') AND
                                            aropen_amount - aropen_paid != 0
                                        THEN
                                            aropen_doctype||'-'||aropen_docnumber||' / '||aropen_docdate||' / '|| formatmoney(aropen_amount - aropen_paid)|| E'\n'
                                        WHEN
                                            aropen_doctype IN ('C') AND
                                            (aropen_amount - aropen_paid) * -1 != 0
                                        THEN
                                            aropen_doctype||'-'||aropen_docnumber||' / '||aropen_docdate||' / '|| formatmoney((aropen_amount - aropen_paid) * -1)|| E'\n'
                                        ELSE
                                            ''
                                    END,
                                    '')
                INTO vArOpenCurrentYearBal, vArOpenCurrentYearBalDocs
                FROM public.aropen
                    JOIN public.yearperiod
                        ON aropen_distdate <@ daterange(yearperiod_start, yearperiod_end, '[]')
                WHERE aropen_open
                    AND yearperiod_id = pYearPeriodId
                    AND yearperiod_start >= (SELECT yearperiod_start FROM public.yearperiod WHERE yearperiod_id = vCashAccFirstYearPeriodId);

                IF coalesce(vArOpenCurrentYearBal, 0) != 0 THEN
                    PERFORM
                        public.insertintoglseries(
                            vGlSequence,
                            'G/L',
                            'JE',
                            vCashAdjDocNum,
                            vArCashAdjAccntId,
                            vArOpenCurrentYearBal,
                            vCurrentYearEnd,
                            'Year Ending '||vCurrentYearEnd||' AR Cash Accounting Adjustment; AR reversal' || vArOpenCurrentYearBalDocs,
                            null);
                    PERFORM
                        public.insertintoglseries(
                            vGlSequence,
                            'G/L',
                            'JE',
                            vCashAdjDocNum,
                            vRevCashAdjAccntId,
                            vArOpenCurrentYearBal * -1,
                            vCurrentYearEnd,
                            'Year Ending '||vCurrentYearEnd||' Rev. Cash Accounting Adjustment; AR reversal' || vArOpenCurrentYearBalDocs,
                            null);
                END IF;


                -- Deal with Open AR from prior years, closed this year
                SELECT
                     SUM(
                        CASE
                            WHEN
                                coalesce(arapply_source_doctype, '') = 'C' AND
                                coalesce(src.aropen_id, -1) > 0
                            THEN
                                -- This is an Allowance Credit Memo created this
                                -- year, but applied to last year's AR.
                                arapply_target_paid
                            WHEN
                                coalesce(arapply_source_doctype, '') IN ('R', 'K')
                            THEN
                                -- This is cash received this year or applied
                                -- from Deferred Revenue this year to a prior
                                -- year AR item.
                                arapply_target_paid
                            ELSE
                                -- We don't know what this is.
                                0.00
                            END

                        )
                    ,E'\n\nDocument Details:\n---------------------------------------------\n'::text ||
                        string_agg(
                             CASE
                                WHEN
                                    coalesce(arapply_source_doctype, '') = 'C' AND
                                    coalesce(src.aropen_id, -1) > 0 AND
                                    arapply_target_paid != 0
                                THEN
                                    arapply_source_doctype||'-'||arapply_source_docnumber||' / '||src.aropen_docdate||' / '||formatmoney(arapply_target_paid)||' applied to '||arapply_target_doctype||'-'||arapply_target_docnumber||' / '||targ.aropen_docdate||' on '||arapply_postdate|| E'\n'
                                WHEN
                                    coalesce(arapply_source_doctype, '') IN ('R', 'K') AND
                                    arapply_target_paid != 0
                                THEN
                                    arapply_source_doctype||'-'||arapply_source_docnumber||' / '||coalesce(coalesce(src.aropen_docdate, arapply_postdate)::text,'')||' / '||formatmoney(arapply_target_paid)||' applied to '||arapply_target_doctype||'-'||arapply_target_docnumber||' / '||targ.aropen_docdate||' on '||arapply_postdate|| E'\n'
                                ELSE
                                    ''
                            END,
                            '')
                INTO vArOpenLastClosedCurrent, vArOpenLastClosedCurrentDocs
                FROM public.arapply
                    JOIN public.aropen targ
                        ON arapply_target_aropen_id = targ.aropen_id
                    JOIN public.yearperiod
                        ON arapply_distdate <@ daterange(yearperiod_start, yearperiod_end, '[]')
                    LEFT OUTER JOIN public.aropen src
                        ON arapply_source_aropen_id = src.aropen_id
                            AND src.aropen_distdate <@ daterange(yearperiod_start, yearperiod_end, '[]')
                WHERE NOT arapply_reversed
                    AND yearperiod_id = pYearPeriodId
                    AND yearperiod_start >= (SELECT yearperiod_start FROM public.yearperiod WHERE yearperiod_id = vCashAccFirstYearPeriodId)
                    AND targ.aropen_distdate < yearperiod_start;

                IF coalesce(vArOpenLastClosedCurrent, 0) != 0 THEN
                    PERFORM
                        public.insertintoglseries(
                            vGlSequence,
                            'G/L',
                            'JE',
                            vCashAdjDocNum,
                            vArCashAdjAccntId,
                            vArOpenLastClosedCurrent * -1,
                            vCurrentYearEnd,
                            'Year Ending '||vCurrentYearEnd||' AR Cash Accounting Adjustment; Open Last Year/Closed This Year' || vArOpenLastClosedCurrentDocs,
                            null);
                    PERFORM
                        public.insertintoglseries(
                            vGlSequence,
                            'G/L',
                            'JE',
                            vCashAdjDocNum,
                            vRevCashAdjAccntId,
                            vArOpenLastClosedCurrent,
                            vCurrentYearEnd,
                            'Year Ending '||vCurrentYearEnd||' Rev. Cash Accounting Adjustment; Open Last Year/Closed This Year' || vArOpenLastClosedCurrentDocs,
                            null);
                END IF;

                -- Deal with Open AP opened this fiscal year
                SELECT
                     SUM(
                        CASE
                            WHEN apopen_doctype IN ('V', 'D') THEN
                                (apopen_amount - apopen_paid)
                            WHEN apopen_doctype IN ('C') THEN
                                (apopen_amount - apopen_paid) * -1
                            ELSE
                                0.00
                            END
                        )
                    ,E'\n\nDocument Details:\n---------------------------------------------\n'::text ||
                        string_agg(CASE
                                        WHEN
                                            apopen_doctype IN ('V', 'D') AND
                                            apopen_amount - apopen_paid != 0
                                        THEN
                                            apopen_doctype||'-'||apopen_docnumber||' / '||apopen_docdate||' / '|| formatmoney(apopen_amount - apopen_paid) || E'\n'
                                        WHEN
                                            apopen_doctype IN ('C') AND
                                            (apopen_amount - apopen_paid) * -1 != 0
                                        THEN
                                            apopen_doctype||'-'||apopen_docnumber||' / '||apopen_docdate||' / '|| formatmoney((apopen_amount - apopen_paid) * -1) || E'\n'
                                        ELSE
                                            ''
                                    END,
                                    '')
                INTO vApOpenCurrentYearBal, vApOpenCurrentYearBalDocs
                FROM public.apopen
                    JOIN public.yearperiod
                        ON apopen_distdate <@ daterange(yearperiod_start, yearperiod_end, '[]')
                WHERE apopen_open
                    AND yearperiod_id = pYearPeriodId
                    AND yearperiod_start >= (SELECT yearperiod_start FROM public.yearperiod WHERE yearperiod_id = vCashAccFirstYearPeriodId);

                IF coalesce(vApOpenCurrentYearBal, 0) != 0 THEN
                    PERFORM
                        public.insertintoglseries(
                            vGlSequence,
                            'G/L',
                            'JE',
                            vCashAdjDocNum,
                            vApCashAdjAccntId,
                            vApOpenCurrentYearBal * -1,
                            vCurrentYearEnd,
                            'Year Ending '||vCurrentYearEnd||' AP Cash Accounting Adjustment; AP reversal' || vApOpenCurrentYearBalDocs,
                            null);
                    PERFORM
                        public.insertintoglseries(
                            vGlSequence,
                            'G/L',
                            'JE',
                            vCashAdjDocNum,
                            vExpCashAdjAccntId,
                            vApOpenCurrentYearBal,
                            vCurrentYearEnd,
                            'Year Ending '||vCurrentYearEnd||' Exp. Cash Accounting Adjustment; AP reversal' || vApOpenCurrentYearBalDocs,
                            null);
                END IF;

                -- Deal with Open AP from prior years, closed this year
                SELECT
                     SUM(
                        CASE
                            WHEN
                                coalesce(apapply_source_doctype, '') = 'C' AND
                                coalesce(src.apopen_id, -1) > 0
                            THEN
                                -- This is an Vendor Credit Memo created this
                                -- year, but applied to a prior year's AP.
                                apapply_target_paid
                            WHEN
                                coalesce(apapply_source_doctype, '') = 'K'
                            THEN
                                -- This is a payment made this year and applied
                                -- to a prior year's AP item, so we expense it
                                -- this year.
                                apapply_target_paid
                            ELSE
                                -- We don't know what this is.
                                0.00
                            END
                        )
                    ,E'\n\nDocument Details:\n---------------------------------------------\n'::text ||
                        string_agg(
                             CASE
                                WHEN
                                    coalesce(apapply_source_doctype, '') = 'C' AND
                                    coalesce(src.apopen_id, -1) > 0 AND
                                    apapply_target_paid != 0
                                THEN
                                    apapply_source_doctype||'-'||apapply_source_docnumber||' / '||src.apopen_docdate||' / '||formatmoney(apapply_target_paid)||' applied to '||apapply_target_doctype||'-'||apapply_target_docnumber||' / '||targ.apopen_docdate||' on '||apapply_postdate|| E'\n'
                                WHEN
                                    coalesce(apapply_source_doctype, '') IN ('R', 'K') AND
                                    apapply_target_paid != 0
                                THEN
                                    apapply_source_doctype||'-'||apapply_source_docnumber||' / '||coalesce(coalesce(src.apopen_docdate, apapply_postdate)::text,'')||' / '||formatmoney(apapply_target_paid)||' applied to '||apapply_target_doctype||'-'||apapply_target_docnumber||' / '||targ.apopen_docdate||' on '||apapply_postdate|| E'\n'
                                ELSE
                                    ''
                            END,
                            '')
                INTO vApOpenLastClosedCurrent, vApOpenLastClosedCurrentDocs
                FROM public.apapply
                    JOIN public.apopen targ
                        ON apapply_target_apopen_id = targ.apopen_id
                    JOIN public.yearperiod
                        ON apapply_postdate <@ daterange(yearperiod_start, yearperiod_end, '[]')
                    LEFT OUTER JOIN public.apopen src
                        ON apapply_source_apopen_id = src.apopen_id
                            AND src.apopen_distdate <@ daterange(yearperiod_start, yearperiod_end, '[]')
                WHERE NOT apapply_reversed
                    AND yearperiod_id = pYearPeriodId
                    AND yearperiod_start >= (SELECT yearperiod_start FROM public.yearperiod WHERE yearperiod_id = vCashAccFirstYearPeriodId)
                    AND targ.apopen_distdate < yearperiod_start;

                IF coalesce(vApOpenLastClosedCurrent, 0) != 0 THEN
                    PERFORM
                        public.insertintoglseries(
                            vGlSequence,
                            'G/L',
                            'JE',
                            vCashAdjDocNum,
                            vApCashAdjAccntId,
                            vApOpenLastClosedCurrent,
                            vCurrentYearEnd,
                            'Year Ending '||vCurrentYearEnd||' AP Cash Accounting Adjustment; Open Last Year/Closed This Year' || vApOpenLastClosedCurrentDocs,
                            null);
                    PERFORM
                        public.insertintoglseries(
                            vGlSequence,
                            'G/L',
                            'JE',
                            vCashAdjDocNum,
                            vExpCashAdjAccntId,
                            vApOpenLastClosedCurrent * -1,
                            vCurrentYearEnd,
                            'Year Ending '||vCurrentYearEnd||' Exp. Cash Accounting Adjustment; Open Last Year/Closed This Year' || vApOpenLastClosedCurrentDocs,
                            null);
                END IF;

                -- Return GL Seq if we actually created a series
                IF
                    coalesce(vArOpenCurrentYearBal, 0) != 0 OR
                    coalesce(vArOpenLastClosedCurrent, 0) != 0 OR
                    coalesce(vApOpenCurrentYearBal, 0) != 0 OR
                    coalesce(vApOpenLastClosedCurrent, 0) != 0
                THEN
                    RETURN vGlSequence;
                ELSE
                    RETURN null::integer;
                END IF;
            END;
        $BODY$
    LANGUAGE plpgsql VOLATILE;

ALTER FUNCTION musecashacc.create_cash_acc_je(pYearPeriodId integer)
    OWNER TO admin;

REVOKE EXECUTE ON FUNCTION musecashacc.create_cash_acc_je(pYearPeriodId integer) FROM public;
GRANT EXECUTE ON FUNCTION musecashacc.create_cash_acc_je(pYearPeriodId integer) TO admin;
GRANT EXECUTE ON FUNCTION musecashacc.create_cash_acc_je(pYearPeriodId integer) TO xtrole;


COMMENT ON FUNCTION musecashacc.create_cash_acc_je(pYearPeriodId integer)
    IS $DOC$If a given yearperiod being closed is subject to cash accounting adjustments, we create the necessary journal entries in this function.$DOC$;
