from artifact_tool import Workbook, SpreadsheetFile
from pathlib import Path

root=Path(__file__).resolve().parents[1]
out=root/'KLOP_Integrated_Tracker_v1.3_DRAFT.xlsx'
wb=Workbook.create()
navy='#10253E'; teal='#116A73'; pale='#EAF2F5'; amber='#FFF2D7'; red='#FCE8E6'; white='#FFFFFF'; green='#E6F4EA'

# Helpers

def make(name,headers,rows,widths=None):
    ws=wb.worksheets.add(name)
    cols=len(headers)
    ws.get_range_by_indexes(0,0,1,cols).values=[headers]
    if rows: ws.get_range_by_indexes(1,0,len(rows),cols).values=rows
    head=ws.get_range_by_indexes(0,0,1,cols)
    head.format={'fill':navy,'font':{'bold':True,'color':white},'row_height':29,'vertical_alignment':'center','wrap_text':True}
    if rows:
        data=ws.get_range_by_indexes(1,0,len(rows),cols)
        data.format.row_height=27
        data.format.wrap_text=True
    for j,w in enumerate(widths or [20]*cols):
        ws.get_range_by_indexes(0,j,max(2,len(rows)+1),1).format.column_width=w
    ws.freeze_panes.freeze_rows(1)
    return ws

summary=[
    ['Checkpoint source','KLOP-PLATFORM-DB-DEV-CHECKPOINT-1.2.1-FROZEN-20261118','IMMUTABLE'],
    ['Delivery version','KLOP-PLATFORM-INTEGRATED-1.3-DRAFT','DRAFT'],
    ['Design baseline v1.1','FROZEN','UNCHANGED'],
    ['DB v1.2 + v1.2.1','Executed Development without error','USER-REPORTED'],
    ['Read-only validation v1.2.1','PASS reported','USER-REPORTED'],
    ['New SQL v1.3','9 auth/session/read SPs; grants + read-only checks','NOT DEPLOYED'],
    ['Backend solution','ASP.NET Core + Dapper/SqlClient + JWT + SMTP','CODE PREPARED'],
    ['Automated testing','Unit + integration + concurrency harness','NOT RUN'],
    ['SQL Server verification','DB clone _TEST required for integration','NOT RUN'],
    ['Release approval','No Production deployment or freeze approval','PENDING']]
ws=make('Overview',['Area','Description','Verified status'],summary,[29,73,24]);ws.get_range('A1:C1').format.fill=teal

sp_rows=[
('iam.usp_RegisterLocalUser','EXISTING','POST /auth/register','v1.2.1','UNCHANGED'),
('iam.usp_ConfirmEmail','EXISTING','POST /auth/verify-email','v1.2.1','UNCHANGED'),
('ten.usp_CreateTenantWithOwner','EXISTING','POST /tenants','v1.2.1','UNCHANGED'),
('ten.usp_InviteExistingUser','EXISTING','POST /tenants/{id}/invitations','v1.2.1','UNCHANGED'),
('ten.usp_AcceptMembership','EXISTING','POST /tenants/memberships/{id}/accept','v1.2.1','UNCHANGED'),
('ten.usp_RemoveTenantMember','EXISTING','DELETE /tenants/{id}/memberships/{id}','v1.2.1','UNCHANGED'),
('iam.usp_AssignTenantRole','EXISTING','POST /tenants/{id}/memberships/{id}/roles','v1.2.1','UNCHANGED'),
('iam.usp_RevokeTenantRole','EXISTING','DELETE /tenants/{id}/memberships/{id}/roles/{code}','v1.2.1','UNCHANGED'),
('mst.usp_OrganizationType_GetAll','EXISTING','GET /master/organization-types','v1.1','UNCHANGED'),
('iam.usp_GetLocalLoginCandidate','NEW','POST /auth/login','v1.3','NOT EXECUTED'),
('iam.usp_RecordLocalLoginFailure','NEW','POST /auth/login','v1.3','NOT EXECUTED'),
('iam.usp_IssueEmailVerificationChallenge','NEW','POST /auth/resend-verification','v1.3','NOT EXECUTED'),
('iam.usp_CreateAuthSession','NEW','POST /auth/login','v1.3','NOT EXECUTED'),
('iam.usp_ValidateSessionAccess','NEW','All protected APIs','v1.3','NOT EXECUTED'),
('iam.usp_RotateRefreshToken','NEW','POST /auth/refresh','v1.3','NOT EXECUTED'),
('iam.usp_RevokeAuthSession','NEW','POST /auth/logout','v1.3','NOT EXECUTED'),
('iam.usp_GetUserProfile','NEW','GET /auth/me','v1.3','NOT EXECUTED'),
('ten.usp_ListMyTenants','NEW','GET /tenants/mine','v1.3','NOT EXECUTED')]
make('SP Contract',['Stored Procedure','Type','API mapping','Source','Runtime status'],[list(x) for x in sp_rows],[37,14,52,17,19])

endpoint_rows=[
('POST','/api/v1/auth/register','Anonymous','Registration, SMTP code'),
('POST','/api/v1/auth/resend-verification','Anonymous','Resend/email recovery'),
('POST','/api/v1/auth/verify-email','Anonymous','One-time challenge'),
('POST','/api/v1/auth/login','Anonymous','Password verification; JWT; cookie'),
('POST','/api/v1/auth/refresh','Refresh cookie + Origin','Rotate one-time refresh'),
('POST','/api/v1/auth/logout','JWT','Session revocation'),
('GET','/api/v1/auth/me','JWT','User profile'),
('GET','/api/v1/master/organization-types','Public','DB-driven master'),
('GET','/api/v1/tenants/mine','JWT','Active memberships'),
('POST','/api/v1/tenants/','JWT','PERSONAL/ORGANIZATION'),
('POST','/api/v1/tenants/{tenantId}/invitations','JWT + tenant.members.invite','Invite verified existing user'),
('POST','/api/v1/tenants/memberships/{membershipId}/accept','JWT + invitee SP check','Accept invite'),
('DELETE','/api/v1/tenants/{tenantId}/memberships/{membershipId}','JWT + tenant.members.remove','Remove member'),
('POST','/api/v1/tenants/{tenantId}/memberships/{membershipId}/roles','JWT + tenant.roles.assign','Assign TENANT role'),
('DELETE','/api/v1/tenants/{tenantId}/memberships/{membershipId}/roles/{roleCode}','JWT + tenant.roles.assign','Revoke TENANT role')]
make('API Inventory',['Verb','Path','Authorization','Purpose'],[list(x) for x in endpoint_rows],[14,78,37,45])

spec=[
('T01','Register+atomic audit','Integration','automated partial','NOT RUN','New user, credential, challenge and audit committed'),
('T02','Duplicate normalized email','Integration','automated partial','NOT RUN','Duplicate rejection with no new user'),
('T03','Confirm email exactly once','Integration','manual','NOT RUN','Replay blocked'),
('T04','Expired challenge rejection','Integration','manual','NOT RUN','Verified field unchanged'),
('T05','PERSONAL tenant one owner','Integration','automated','NOT RUN','One active owner'),
('T06','ORGANIZATION tenant PENDING','Integration','automated partial','NOT RUN','PENDING + UNVERIFIED'),
('T07','Unverified or duplicate tenant','Integration','manual','NOT RUN','No orphan records'),
('T08','Invite member','Integration','automated','NOT RUN','Invited status and events'),
('T09','Accept invite','Integration','automated','NOT RUN','Active + MEMBER role'),
('T10','Foreign tenant actor','Security','manual','NOT RUN','Forbidden and unchanged'),
('T11','Cross-scope role assignment','Security','manual','NOT RUN','PLATFORM role rejected'),
('T12','Unauthorized OWNER assignment','Security','manual','NOT RUN','Privilege escalation rejected'),
('T13','Revoke last owner PERSONAL','Security','automated','NOT RUN','Rejected owner still active'),
('T14','Remove last owner PERSONAL','Security','automated','NOT RUN','Rejected owner still active'),
('T15','Concurrent owner revokes ORG','Concurrency','automated','NOT RUN','Exactly one succeeds, one owner survives'),
('T16','Remove non-owner member','Integration','manual','NOT RUN','Membership removed; roles deleted; audit'),
('T17','Audit insert failure rollback','Atomicity','manual','NOT RUN','Full transaction rollback'),
('T18','Runtime principal denies DML','Security','manual','NOT RUN','Exec-only; direct DML denied'),
('T19','Spoof ActorUserId request','API security','manual','NOT RUN','Body actor ignored; JWT authoritative'),
('T20','Invalid master code','Integration','automated','NOT RUN','No mutation; rejected'),
('T21','Closed/suspended tenant mutation','Security','manual','NOT RUN','Denied by SP'),
('T22','Session/JWT validation','Security','automated partial','NOT RUN','Revoked session cannot authorize'),
('T23','Login invalid password lockout','Security','manual','NOT RUN','Rate limit and lockout enforced'),
('T24','JWT issuer/audience/expiry','Security','manual','NOT RUN','Invalid JWT denied'),
('T25','Refresh rotation + replay','Integration','automated','NOT RUN','Reuse revokes session'),
('T26','Logout revoke session','Integration','manual','NOT RUN','Access/refresh unusable'),
('T27','SMTP outage + resend','Reliability','manual','NOT RUN','Committed user can recover'),
('T28','Tenant isolation stale membership','Security','manual','NOT RUN','Former member denied immediately'),
('T29','Key Vault/Managed Identity','Operations','manual','NOT RUN','No plaintext secrets, fail closed'),
('T30','CSRF/Origin and secure cookies','Security','manual','NOT RUN','Cross-origin refresh rejected'),
('T31','Production TLS and permission check','Operations','manual','NOT RUN','DB TLS; least privilege'),
('T32','REST API end-to-end flow','API','manual','NOT RUN','Registration to tenant role flow'),
]
ws=make('Test Matrix',['Test ID','Scenario','Category','Coverage','Status','Expected result','Observed','Evidence link / file','Reviewer'],
    [[*x,'','',''] for x in spec],[14,43,20,21,16,58,42,52,20])
ws.get_range('E2:E250').data_validation={"rule":{"type":"list","values":["NOT RUN","PASS","FAIL","BLOCKED","SKIPPED"]}}
ws.get_range('E2:E40').conditional_formats.add_custom('=E2="FAIL"',{'fill':red})
ws.get_range('E2:E40').conditional_formats.add_custom('=E2="PASS"',{'fill':green})

risk_rows=[
('R01','P0','.NET build and restore not executed','Build with .NET SDK; lock dependency versions','OPEN'),
('R02','P0','v1.3 auth/session SQL not deployed or run','DBA review + isolated Development execution','OPEN'),
('R03','P0','Functional/security integration tests not run','Clone _TEST and execute all, retain evidence','OPEN'),
('R04','P1','SMTP not transactional with registration','Resend + future durable outbox','OPEN'),
('R05','P0','Existing source repo not integrated','Compare/merge against actual KLOP PLATFORM repo','OPEN'),
('R06','P1','Azure Entra + OIDC/OpenIddict not included','Separate approved auth scope','OPEN'),
('R07','P1','Key rotation/JWKS overlap not implemented','Operational key lifecycle design','OPEN'),
('R08','P1','Release-ready distributed rate limit absent','Proxy-aware and distributed enforcement','OPEN'),
('R09','P1','Audit/retention operational review pending','Compliance/backup/recovery/retention policy','OPEN'),
('R10','P0','Many-to-many vs legacy single tenant contradiction','Formal Architecture Change Request','OPEN'),
('R11','P1','Sample integration test assertions use one test identity','Separate API runtime and fixture verification principals','OPEN'),
('R12','P1','net8.0 support status requires verification','Review support window / upgrade target before Prod','OPEN')]
ws=make('Risk Register',['ID','Severity','Risk','Required action','Status'],[list(x) for x in risk_rows],[11,13,62,70,14]);ws.get_range('E2:E30').data_validation={"rule":{"type":"list","values":["OPEN","MITIGATED","ACCEPTED","CLOSED"]}}

file_rows=[
('sql/010_preflight_READONLY.sql','Preflight metadata (no changes)','READ-ONLY'),
('sql/050_config_seed_DEVELOPMENT_REVIEW.sql','Proposed SQL runtime config keys','REVIEW BEFORE USE'),
('sql/100_auth_session_delta.sql','9 new or altered auth/session SPs','DRAFT / NOT EXECUTED'),
('sql/200_grants_TEMPLATE.sql','Additional DBA GRANT EXECUTE template','REVIEW BEFORE USE'),
('sql/300_postdeploy_READONLY.sql','SQL procedure inventory check','READ-ONLY'),
('sql/400_invariants_READONLY.sql','Owner/integrity checks','READ-ONLY'),
('src/','Four-project backend source','SOURCE ONLY'),
('tests/','xUnit and SQL clone harness','NOT RUN'),
('deploy/docker-compose.mailpit.yml','Optional local SMTP inbox','OPTIONAL'),
('docs/','Technical/security/runbook documentation','DRAFT'),
('KLOP_Integrated_Tracker_v1.3_DRAFT.xlsx','Status/test/risk/contract source','DRAFT')]
make('Artifact Register',['Artifact','Purpose','Status'],[list(x) for x in file_rows],[64,62,23])

config_rows=[
('auth.jwt.issuer','PLAIN','SQL cfg','Development issuer URL','NEW / DRAFT'),
('auth.jwt.audience','PLAIN','SQL cfg','JWT audience','NEW / DRAFT'),
('web.allowed_origin','PLAIN','SQL cfg','Allowed SPA origin','NEW / DRAFT'),
('smtp.host','PLAIN','SQL cfg','SMTP relay host','NEW / DRAFT'),
('smtp.port','PLAIN','SQL cfg','SMTP relay port','NEW / DRAFT'),
('smtp.from','PLAIN','SQL cfg','SMTP sender','NEW / DRAFT'),
('smtp.require_tls','PLAIN','SQL cfg','TLS required in Production','NEW / DRAFT'),
('smtp.username','PLAIN','SQL cfg','Optional SMTP username','NEW / DRAFT'),
('auth.signing_key_ref','KEYVAULT_REFERENCE','SQL cfg','Vault secret name only','NEW / DRAFT'),
('smtp.password_ref','KEYVAULT_REFERENCE','SQL cfg','Vault secret name only','NEW / DRAFT'),
('auth.email_verification_hours','PLAIN','SQL cfg','Verification expiry','NEW / DRAFT'),
('security.login_lockout_minutes','PLAIN','SQL cfg','Lockout duration','NEW / DRAFT'),
('auth.access_token_minutes','PLAIN','SQL cfg','JWT lifetime','EXISTING / FROZEN'),
('auth.refresh_token_days','PLAIN','SQL cfg','Session / refresh lifetime','EXISTING / FROZEN'),
('security.max_login_attempts','PLAIN','SQL cfg','Login failure policy','EXISTING / FROZEN'),
('security.password.min_length','PLAIN','SQL cfg','Registration password minimum','EXISTING / FROZEN'),
('registration.personal.enabled','PLAIN','SQL cfg','Personal registration switch','EXISTING / FROZEN'),
('registration.organization.enabled','PLAIN','SQL cfg','Organization registration switch','EXISTING / FROZEN'),
]
make('Configuration Keys',['Key','Storage type','Source','Purpose','Status'],[list(x) for x in config_rows],[48,24,18,58,23])


# Summary numbers and formulas tied to actual tracker data, no hardcoded displayed KPIs.
dash=wb.worksheets.add('Dashboard')
dash.merge_cells('A1:D1');dash.get_range('A1').values=[['KLOP INTEGRATED DEVELOPMENT — v1.3 DRAFT']]
dash.get_range('A1:D1').format={'fill':navy,'font':{'bold':True,'color':white,'size':15},'row_height':36}
dash.get_range('A3:B8').values=[['Metric','Count'],['Test cases',None],['PASS',None],['FAIL',None],['NOT RUN',None],['OPEN risks',None]]
dash.get_range('B4').formulas=[['=COUNTA(\'Test Matrix\'!A2:A200)']]
dash.get_range('B5').formulas=[['=COUNTIF(\'Test Matrix\'!E2:E200,"PASS")']]
dash.get_range('B6').formulas=[['=COUNTIF(\'Test Matrix\'!E2:E200,"FAIL")']]
dash.get_range('B7').formulas=[['=COUNTIF(\'Test Matrix\'!E2:E200,"NOT RUN")']]
dash.get_range('B8').formulas=[['=COUNTIF(\'Risk Register\'!E2:E100,"OPEN")']]
dash.get_range('A3:B3').format={'fill':teal,'font':{'bold':True,'color':white}}
dash.get_range('A1:A12').format.column_width=35;dash.get_range('B1:B12').format.column_width=20
dash.merge_cells('A10:D10');dash.get_range('A10').values=[['Status: PREPARED — not compiled, not executed, not approved for Production']]
dash.get_range('A10:D10').format={'fill':amber,'font':{'bold':True}}
dash.merge_cells('A12:D12');dash.get_range('A12').values=[['Source: immutable checkpoint KLOP-PLATFORM-DB-DEV-CHECKPOINT-1.2.1-FROZEN-20261118']]
dash.get_range('A12:D12').format.wrap_text=True

try:
    print(wb.inspect({'kind':'table','range':'Dashboard!A3:B8','include':'values,formulas','table_max_rows':8,'table_max_cols':2}).ndjson[:1800])
except Exception as e:
    print('inspect note:', type(e).__name__, str(e)[:200])
SpreadsheetFile.export_xlsx(wb).save(str(out))
print('EXPORTED',out,out.stat().st_size)
