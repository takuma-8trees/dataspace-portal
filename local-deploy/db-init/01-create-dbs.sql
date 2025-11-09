-- Create databases required by local stack
-- This script runs when Postgres initializes a new data directory.

-- Create Keycloak DB
CREATE DATABASE keycloak;

-- Create Authority Portal DB referenced by backend/crawler
CREATE DATABASE authority_portal;

-- Note: the default owner will be the Postgres superuser (the container's POSTGRES_USER).
-- If you need specific owners or extensions, add them here.
