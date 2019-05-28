/*************************************************************************
 *************************************************************************
 **
 ** File:         create_early_musemetrics.sql
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
-- If true, the system will try to book cash accounting related journal entries
-- when the fiscal year is closed.  If false, this extension is bypassed.
--

SELECT musextputils.create_musemetric(  'musecashacc'
                                       ,'isCashAccEnabled'
                                       ,'If true, the system will try to book cash accounting related journal entries when the fiscal year is closed.  If false, this extension is bypassed.'
                                       ,true
                                    )
    WHERE musextputils.get_musemetric(  'musecashacc'
                                       ,'isCashAccEnabled'
                                       ,null::boolean) IS NULL;

--
-- The first period for which the cash accounting extension should try to create
-- cash accounting related JEs.  This setting is needed since a common way of
-- correcting a corrupted xTuple trial balance is to open/close periods.  Since
-- there may be a period in which this extension was not used involved, we
-- shouldn't try to work under those circumstances.
--

SELECT musextputils.create_musemetric(  'musecashacc'
                                       ,'cashAccFirstYearPeriodId'
                                       ,'The first period for which the cash accounting extension should try to create cash accounting related JEs.  This setting is needed since a common way of correcting a corrupted xTuple trial balance is to open/close periods.  Since there may be a period in which this extension was not used involved, we shouldn''t try to work under those circumstances.'
                                       ,(SELECT yearperiod_id::numeric
                                         FROM public.yearperiod
                                         WHERE now()::date <@ daterange(yearperiod_start, yearperiod_end, '[]')
                                            AND NOT yearperiod_closed)
                                    )
    WHERE musextputils.get_musemetric(  'musecashacc'
                                       ,'cashAccFirstYearPeriodId'
                                       ,null::numeric) IS NULL;

--
-- Accounts Receivable cash accounting adjustment account.  This should be an
-- asset contra-account for adjusting AR at year's close.
--

SELECT musextputils.create_musemetric(  'musecashacc'
                                       ,'arCashAdjAccntId'
                                       ,'Accounts Receivable cash accounting adjustment account.  This should be an asset contra-account for adjusting AR at year''s close.'
                                       ,-1::numeric
                                    )
    WHERE musextputils.get_musemetric(  'musecashacc'
                                       ,'arCashAdjAccntId'
                                       ,null::numeric) IS NULL;

--
-- Revenue cash accounting adjustment account.  This should be a revenue contra
-- account for adjusting revenue at year's close.
--

SELECT musextputils.create_musemetric(  'musecashacc'
                                       ,'revCashAdjAccntId'
                                       ,'Revenue cash accounting adjustment account.  This should be a revenue contra account for adjusting revenue at year''s close.'
                                       ,-1::numeric
                                    )
    WHERE musextputils.get_musemetric(  'musecashacc'
                                       ,'revCashAdjAccntId'
                                       ,null::numeric) IS NULL;

--
-- Accounts Payable cash accounting adjustment account.  This should be an
-- asset contra-account for AP at year's close.
--

SELECT musextputils.create_musemetric(  'musecashacc'
                                       ,'apCashAdjAccntId'
                                       ,'Accounts Payable cash accounting adjustment account.  This should be an asset contra-account for AP at year''s close.'
                                       ,-1::numeric
                                    )
    WHERE musextputils.get_musemetric(  'musecashacc'
                                       ,'apCashAdjAccntId'
                                       ,null::numeric) IS NULL;

--
-- Expense cash accounting adjustment account.  This should be a expense contra
-- account for adjusting AP at year's close.
--

SELECT musextputils.create_musemetric(  'musecashacc'
                                       ,'expCashAdjAccntId'
                                       ,'Expense cash accounting adjustment account.  This should be a expense contra account for adjusting AP at year''s close.'
                                       ,-1::numeric
                                    )
    WHERE musextputils.get_musemetric(  'musecashacc'
                                       ,'expCashAdjAccntId'
                                       ,null::numeric) IS NULL;