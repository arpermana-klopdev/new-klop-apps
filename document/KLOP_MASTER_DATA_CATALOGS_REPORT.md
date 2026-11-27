# Master Data — active reference catalogs

Issue #9. Source development only while SQL and live Development validation are HOLD.

## API / UI
- Existing `GET /api/v1/master/organization-types` is unchanged. New public reference-only `GET /api/v1/master/tenant-types` uses existing `IPlatformRepository.TenantTypes`, mapped to `mst.usp_TenantType_GetAll` with ActiveOnly=true. The handler filters active rows and projects only code/name. No tenant records, role grants, configuration, or personal data are returned. Catalog availability does not imply registration or authorization eligibility.
- Both procedures already appear in the v1.10 runtime allowlist. The frozen v1.1 definition was inspected read-only and returns active master rows. No SQL or grants changed, no claim of live database state.
- Platform Setup > Master Data shows both catalogs, independent search/count, refresh/retry, loading, error, empty and no-match states. No generic write API or editing controls. All rows come from API responses.
- OpenAPI and generated TypeScript updated, route inventory test updated, two UI regression cases added. CI evidence recorded on PR; live API calls not run.

## Deferred
Catalog administration, inactive-row management, validation, approval, audit and dedicated PLATFORM permissions require approved contracts and versioned SQL; remain HOLD. Existing SQL reconciliation, deployment and UAT remain owner-held. No automatic deployment or changes to frozen baseline files.
