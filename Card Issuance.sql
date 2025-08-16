/* ===========================
   Card Issuance Lineage & KPIs
   =========================== */

/* Base: one row per issued card token with sequence within acct/holder role */
drop table card_issue_events;

create table card_issue_events parallel nologging as
select
    a.card_acct_id                       as card_acct_id,          
    b.card_open_date                     as card_open_date,         
    a.card_token                         as card_token,            
    a.holder_role                        as holder_role,          
    a.block_code                         as block_code,           
    a.card_issue_date                    as card_issue_date,        
    row_number() over (
        partition by a.card_acct_id, a.holder_role
        order by a.card_issue_date
    )                                    as issuance_seq
from   warehouse.dm_card_detail a,
       warehouse.dm_card b
where  a.card_acct_id = b.card_acct_id
  and (b.card_close_date is null or b.card_close_date >= date '2025-01-01');


/* ----------------------------------------
   Monthly issuance by reason & holder role
   ---------------------------------------- */
select
    to_char(a.card_issue_date, 'YYYY-MM')                                        as issue_month,
    case
        when a.issuance_seq = 1 then 'First Issue'
        when b.block_code is not null then 'Block ' || b.block_code
        else 'No block'
    end                                                                           as issuance_reason,
    count(distinct case when a.holder_role = 'P' then a.card_token end)           as primary_cards,
    count(distinct case when a.holder_role = 'S' then a.card_token end)           as secondary_cards,
    count(distinct a.card_token)                                                  as total_cards
from   card_issue_events a
left join card_issue_events b
       on  a.card_acct_id  = b.card_acct_id
       and a.holder_role   = b.holder_role
       and a.issuance_seq  = b.issuance_seq + 1
where  a.card_issue_date >= date '2025-01-01'
group by
    to_char(a.card_issue_date, 'YYYY-MM'),
    case
        when a.issuance_seq = 1 then 'First Issue'
        when b.block_code is not null then 'Block ' || b.block_code
        else 'No block'
    end
order by 1, 2;


/* ===========================
   Checks / Samples
   =========================== */

-- Raw sample
select * from card_issue_events order by 1, 4, 7;

-- Month breakdown by issuance type
select
    to_char(a.card_issue_date, 'YYYY-MM')                                        as issue_month,
    count(case when a.issuance_seq = 1 then a.card_token end)                    as first_issue,
    count(case when b.block_code = 'L' then a.card_token end)                    as l_block,
    count(case when b.block_code = 'M' then a.card_token end)                    as m_block,
    count(case when b.block_code not in ('L','M') then a.card_token end)         as other_block,
    count(case when a.issuance_seq > 1 and b.block_code is null then a.card_token end)
                                                                                 as no_block,
    count(distinct a.card_token)                                                 as total_cards
from   card_issue_events a
left join card_issue_events b
       on  a.card_acct_id  = b.card_acct_id
       and a.holder_role   = b.holder_role
       and a.issuance_seq  = b.issuance_seq + 1
where  a.card_issue_date >= date '2024-01-01'
group by to_char(a.card_issue_date, 'YYYY-MM')
order by 1;

-- New vs previous card per account/role where predecessor is missing (edge review)
select
    a.card_acct_id,
    a.holder_role,
    a.card_token                                  as new_card_token,
    b.card_token                                  as prior_card_token,
    a.card_open_date,
    a.card_issue_date                             as card_issue_dt,
    case
        when a.issuance_seq = 1 then 'First card'
        when b.block_code = 'L' then 'L Block'
        when b.block_code = 'M' then 'M Block'
        when b.block_code not in ('L','M') then 'Other block'
        when a.issuance_seq > 1 and b.block_code is null then 'No block'
        else 'Unclassified'
    end                                           as issuance_reason
from   card_issue_events a
left join card_issue_events b
       on  a.card_acct_id  = b.card_acct_id
       and a.holder_role   = b.holder_role
       and a.issuance_seq  = b.issuance_seq + 1
where  a.card_issue_date >= date '2024-01-01'
  and  b.card_token is null
order  by 1;

-- Month × role × first-card × prior-block matrix
select
    to_char(a.card_issue_date, 'YYYY-MM')        as issue_month,
    a.holder_role,
    case when a.issuance_seq = 1 then 'Y' else 'N' end as first_card,
    b.block_code,
    count(distinct a.card_token)                  as total_cards
from   card_issue_events a
left join card_issue_events b
       on  a.card_acct_id  = b.card_acct_id
       and a.holder_role   = b.holder_role
       and a.issuance_seq  = b.issuance_seq + 1
where  a.card_issue_date >= date '2025-01-01'
group by
    to_char(a.card_issue_date, 'YYYY-MM'),
    a.holder_role,
    case when a.issuance_seq = 1 then 'Y' else 'N' end,
    b.block_code
order by 1, 2, 3;

