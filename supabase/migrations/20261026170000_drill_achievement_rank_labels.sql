update public.drill_test_definitions
set label = case code
  when 'ACH-1' then 'Achievement 1 (C/Amn)'
  when 'ACH-2' then 'Achievement 2 (C/A1C)'
  when 'ACH-3' then 'Achievement 3 (C/SrA)'
  when 'WBA-2' then 'Wright Brothers Award — Part 2 (C/SSgt)'
  when 'ACH-4' then 'Achievement 4 (C/TSgt)'
  when 'ACH-5' then 'Achievement 5 (C/MSgt)'
  when 'ACH-6' then 'Achievement 6 (C/SMSgt)'
  when 'ACH-7' then 'Achievement 7 (C/CMSgt)'
  when 'ACH-8' then 'Achievement 8 (C/CMSgt Ghost)'
  else label
end,
updated_at = now()
where code in ('ACH-1','ACH-2','ACH-3','WBA-2','ACH-4','ACH-5','ACH-6','ACH-7','ACH-8');
