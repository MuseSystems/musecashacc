/*************************************************************************
 *************************************************************************
 **
 ** File:         reverse_cash_acc_je.sql
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
-- Reverses any previously created cash accounting JEs, if any are active for
-- the fiscal year being opened.
--

CREATE OR REPLACE FUNCTION musecashacc.reverse_cash_acc_je(pYearPeriodId integer)
    RETURNS integer AS
        $BODY$
            DECLARE
                vIsCashAccEnabled boolean := musextputils.get_musemetric('musecashacc', 'isCashAccEnabled', null::boolean);
                vCashAccFirstYearPeriodId integer := musextputils.get_musemetric('musecashacc', 'cashAccFirstYearPeriodId', null::numeric)::integer;

                vTargYearEnd date;
                vReverseJeSeq integer;

                vCashAdjDocNumRoot text;
                vLastCashAdjDocNumSeq text;
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

                -- Get the year end info and assemble our candidate docnum
                SELECT
                     yearperiod_end
                    ,'CSHACC-'||extract(year FROM yearperiod_end)
                INTO vTargYearEnd, vCashAdjDocNumRoot
                FROM public.yearperiod
                WHERE yearperiod_id = pYearPeriodId;

                SELECT
                     max(substring(gltrans_docnumber, '...$'))
                INTO vLastCashAdjDocNumSeq
                FROM public.gltrans
                WHERE gltrans_docnumber ~ ('^'||vCashAdjDocNumRoot);

                IF
                    NOT EXISTS(
                            SELECT true
                            FROM public.gltrans
                            WHERE gltrans_docnumber = (vCashAdjDocNumRoot ||'-'||vLastCashAdjDocNumSeq)
                            GROUP BY gltrans_docnumber
                            HAVING count(DISTINCT gltrans_sequence) = 1)
                THEN
                    RETURN null::integer;
                END IF;

                -- We have work to do, so do it.
                SELECT gltrans_sequence
                INTO vReverseJeSeq
                FROM public.gltrans
                WHERE gltrans_docnumber = vCashAdjDocNumRoot ||'-'||vLastCashAdjDocNumSeq
                ORDER BY gltrans_sequence DESC
                LIMIT 1;


                RETURN public.reverseglseries(
                    vReverseJeSeq,
                    vTargYearEnd,
                    'Reversing Cash Accounting Entries: '||vCashAdjDocNumRoot ||'-'||vLastCashAdjDocNumSeq);

            END;
        $BODY$
    LANGUAGE plpgsql VOLATILE;

ALTER FUNCTION musecashacc.reverse_cash_acc_je(pYearPeriodId integer)
    OWNER TO admin;

REVOKE EXECUTE ON FUNCTION musecashacc.reverse_cash_acc_je(pYearPeriodId integer) FROM public;
GRANT EXECUTE ON FUNCTION musecashacc.reverse_cash_acc_je(pYearPeriodId integer) TO admin;
GRANT EXECUTE ON FUNCTION musecashacc.reverse_cash_acc_je(pYearPeriodId integer) TO xtrole;


COMMENT ON FUNCTION musecashacc.reverse_cash_acc_je(pYearPeriodId integer)
    IS $DOC$Reverses any previously created cash accounting JEs, if any are active for the fiscal year being opened.$DOC$;
