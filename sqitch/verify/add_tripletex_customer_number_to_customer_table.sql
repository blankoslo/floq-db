-- Verify floq:add_tripletex_customer_number_to_customer_table on pg

BEGIN;

do $$
BEGIN
  BEGIN
    insert into customers (id, name, tripletex_number) values('__verify_tripletex_a__', '__verify_tripletex_a__', 99999);
    insert into customers (id, name, tripletex_number) values('__verify_tripletex_b__', '__verify_tripletex_b__', 99999);
    EXCEPTION WHEN unique_violation THEN
      -- SUCCESS: Verified that duplicate tripletex_number gave us unique_violation
      DELETE FROM customers WHERE name IN ('__verify_tripletex_a__', '__verify_tripletex_b__');
      RETURN;
  END;
  DELETE FROM customers WHERE name IN ('__verify_tripletex_a__', '__verify_tripletex_b__');
  RAISE EXCEPTION 'ERROR: Still possible to insert duplicate tripletex_number.';
END;
$$ language 'plpgsql';

ROLLBACK;
