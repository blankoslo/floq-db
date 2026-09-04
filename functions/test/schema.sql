create type time_status as enum ('billable','nonbillable','unavailable');

create table employees (id serial primary key, first_name text, last_name text);
create table customers (id text primary key, name text not null);
create table projects (
  id text primary key,
  name text not null,
  billable time_status not null,
  customer text not null references customers(id)
);
create table time_entry (
  id serial primary key,
  employee integer not null references employees(id),
  minutes integer,
  project text not null references projects(id),
  date date not null
);
create table project_members (
  id text primary key default gen_random_uuid()::text,
  employee_id integer not null references employees(id),
  customer_id text not null references customers(id),
  hourly_rate numeric not null,
  from_date date not null
);
