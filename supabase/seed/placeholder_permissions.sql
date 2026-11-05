-- PLACEHOLDER permission matrix. NOT approved (decision D1 is open).
-- It exists so the system can be developed and tested. Replace with the matrix
-- the committee approves; the app reads permissions from this table at runtime.

insert into public.role_permission (role, permission) values
  ('super_admin',        'family.read'),
  ('super_admin',        'family.write'),
  ('super_admin',        'payment.read'),
  ('super_admin',        'payment.record'),
  ('super_admin',        'payment.verify'),
  ('super_admin',        'payment.reverse'),
  ('super_admin',        'rule.manage'),
  ('super_admin',        'role.manage'),
  ('super_admin',        'audit.read'),
  ('committee_admin',    'family.read'),
  ('committee_admin',    'family.write'),
  ('committee_admin',    'payment.read'),
  ('treasurer',          'family.read'),
  ('treasurer',          'payment.read'),
  ('treasurer',          'payment.verify'),
  ('treasurer',          'payment.reverse'),
  ('collection_officer', 'family.read'),
  ('collection_officer', 'payment.read'),
  ('collection_officer', 'payment.record'),
  ('general_member',     'family.read')
on conflict do nothing;
