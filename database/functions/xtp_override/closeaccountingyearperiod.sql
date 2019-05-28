/*************************************************************************
 *************************************************************************
 **
 ** File:         closeaccountingyearperiod.sql
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
-- Wraps the xTuple ERP stock database function for closing the accounting year
-- and orchestrates our custom logic, if required.
--

CREATE OR REPLACE FUNCTION musecashacc.closeaccountingyearperiod(pYearPeriodId integer)
    RETURNS integer AS
        $BODY$
            DECLARE
                vGlSeqId integer;
                vTransCount integer;
            BEGIN
                vGlSeqId := musecashacc.create_cash_acc_je(pYearPeriodId);

                IF vGlSeqId IS NOT NULL THEN
                    -- We created a cash accounting JE, post it
                    vTransCount := public.postglseries(vGlSeqId);

                    IF coalesce(vTransCount, 0) = 0 THEN
                        RAISE EXCEPTION
                             'We failed to post cash accounting entries as required. (FUNC: musecashacc.closeaccountingyearperiod) (pYearPeriodId: %)'
                            ,pYearPeriodId;

                    END IF;
                END IF;

                RETURN public.closeaccountingyearperiod(pYearPeriodId);

            END;
        $BODY$
    LANGUAGE plpgsql VOLATILE;

ALTER FUNCTION musecashacc.closeaccountingyearperiod(pYearPeriodId integer)
    OWNER TO admin;

REVOKE EXECUTE ON FUNCTION musecashacc.closeaccountingyearperiod(pYearPeriodId integer) FROM public;
GRANT EXECUTE ON FUNCTION musecashacc.closeaccountingyearperiod(pYearPeriodId integer) TO admin;
GRANT EXECUTE ON FUNCTION musecashacc.closeaccountingyearperiod(pYearPeriodId integer) TO xtrole;


COMMENT ON FUNCTION musecashacc.closeaccountingyearperiod(pYearPeriodId integer)
    IS $DOC$Wraps the xTuple ERP stock database function for closing the accounting year and orchestrates our custom logic, if required.$DOC$;
