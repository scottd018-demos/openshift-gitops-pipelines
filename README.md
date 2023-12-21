# Demo Steps

1. **Cloud Administrator Persona** Create ROSA Cluster - This demo expects to be done with a ROSA cluster.  This is the first prerequisite to running the demo.
This expects a multi-az setup, as the underlying infrastructure (RDS) requires it.
2. **Cloud Administrator Persona** Create Infrastructure - This can be done with the `make infra` target (use `make infra-destroy` to teardown).
3. **Platform Engineer Persona** Setup Platform - This can be done with the `make operators` and `make platform` target.  This will do things like install operators, setup permissions, 
and create reusable pipeline tasks.
4. **Developer Persona** - The following needs to be done:
   * Create Project - `make project`
   * Create Infrastructure Connection Info - `make secret`
   * Create Database Seed Data - `make seed`
   * Create Pipelines - `make pipelines`
   * Deploy App - TBD
   * Deploy UI - TBD
