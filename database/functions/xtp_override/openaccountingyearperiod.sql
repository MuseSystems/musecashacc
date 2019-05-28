/*************************************************************************
 *************************************************************************
 **
 ** File:         openaccountingyearperiod.sql
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
-- Wraps the xTuple ERP stock database function for opening a previously closed
-- accounting year and reverses the last cash accounting entry, if one is found.
--

CREATE OR REPLACE FUNCTION musecashacc.openaccountingyearperiod(pYearPeriodId integer)
    RETURNS integer AS
        $BODY$
            DECLARE
                vReturnVal integer;
            BEGIN
                vReturnVal := public.openaccountingyearperiod(pYearPeriodId);

                PERFORM musecashacc.reverse_cash_acc_je(pYearPeriodId);

                RETURN vReturnVal;
            END;
        $BODY$
    LANGUAGE plpgsql VOLATILE;

ALTER FUNCTION musecashacc.openaccountingyearperiod(pYearPeriodId integer)
    OWNER TO admin;

REVOKE EXECUTE ON FUNCTION musecashacc.openaccountingyearperiod(pYearPeriodId integer) FROM public;
GRANT EXECUTE ON FUNCTION musecashacc.openaccountingyearperiod(pYearPeriodId integer) TO admin;
GRANT EXECUTE ON FUNCTION musecashacc.openaccountingyearperiod(pYearPeriodId integer) TO xtrole;


COMMENT ON FUNCTION musecashacc.openaccountingyearperiod(pYearPeriodId integer)
    IS $DOC$Wraps the xTuple ERP stock database function for opening a previously closed accounting year and reverses the last cash accounting entry, if one is found. $DOC$;
