"""Static cross-reference only; not a .NET build or SQL Server test."""
from pathlib import Path
import re,json
root=Path(__file__).resolve().parents[1]
repo=(root/'src/KLOP.Platform.Infrastructure/KlopRepository.cs').read_text()
sql=(root/'sql/100_auth_session_delta.sql').read_text()
old={"iam.usp_RegisterLocalUser","iam.usp_ConfirmEmail","ten.usp_CreateTenantWithOwner",
"ten.usp_InviteExistingUser","ten.usp_AcceptMembership","ten.usp_RemoveTenantMember",
"iam.usp_AssignTenantRole","iam.usp_RevokeTenantRole","mst.usp_OrganizationType_GetAll"}
refs=set(re.findall(r'"((?:iam|ten|mst)\.usp_[A-Za-z0-9_]+)"',repo))
new=set(re.findall(r'CREATE OR ALTER PROCEDURE\s+((?:iam|ten)\.usp_[A-Za-z0-9_]+)',sql,re.I))
assert refs-(old|new)==set(),f'Unknown SP references: {refs-(old|new)}'
assert len(new)==9,f'Expected nine new SPs, got {len(new)}'
assert 'CommandType.StoredProcedure' in repo
assert 'cfg.usp_Configuration_GetByKey' in (root/'src/KLOP.Platform.Infrastructure/RuntimeSettings.cs').read_text()
assert 'auth.signing_key_ref' in (root/'sql/050_config_seed_DEVELOPMENT_REVIEW.sql').read_text()
assert 'aud.SecurityEvents' in sql and 'aud.AuditEvents' in sql
print(json.dumps({'static_status':'PASS','new_stored_procedures':len(new),'repository_sp_refs':len(refs),
    'note':'No .NET compile, no SQL execution, no API execution'},indent=2))
