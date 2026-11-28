"""Build v1.1 offline source projection from the unchanged v1.0 snapshot. Never connect to SQL Server."""
import argparse, hashlib, json, pathlib, sqlite3, shutil, sys
ROOT=pathlib.Path(__file__).resolve().parent
SOURCE='36f563fdcdb70036ad5fd7d16e45c54b520c60a5'
BASE_BLOB='7dc47b14baa7636f1446aeac368b62407bd3f67d'
NOW='2026-11-28T07:53:00.000Z'  # snapshot marker, not deployment time
PERMISSIONS=[
('platform.registrations.read','Read platform registrations','Read registration summaries, applications, profile details, and persisted timelines.',730),
('platform.role_permissions.read','Read role permission matrix','View configured grants, scope eligibility, readiness, restrictions, and audit history.',760),
('platform.role_permissions.update','Update role permission matrix','Validate and save approved role permission changes through a transactional batch.',761),
]+[('platform.legal_documents.'+code,name,desc,710+i) for i,(code,name,desc) in enumerate([
('read','Read legal documents','Read Platform legal document metadata and version history.'),('draft.create','Create legal document drafts','Upload a legal document as a draft version.'),('draft.edit','Edit legal document drafts','Edit metadata and scopes on a draft version.'),('draft.preview','Preview legal document drafts','Preview private draft and pending-approval PDF files.'),('submit','Submit legal documents','Submit a validated draft for approval.'),('approve','Approve legal documents','Approve or reject a submitted legal document.'),('publish','Publish legal documents','Publish an approved legal document version.'),('archive','Archive legal documents','Archive a superseded published legal document version.')])]+[('platform.notifications.'+code,name,desc,810+i) for i,(code,name,desc) in enumerate([
('read','Read notification templates','Read platform notification templates and channel catalog.'),('draft.create','Create notification drafts','Create platform notification template drafts.'),('draft.edit','Edit notification drafts','Edit draft platform notification template versions.'),('draft.preview','Preview notification drafts','Preview drafts with synthetic nonfunctional values.'),('submit','Submit notification templates','Submit notification versions for approval.'),('approve','Approve notification templates','Approve or reject submitted notification versions.'),('activate','Activate notification templates','Activate approved notification versions.'),('archive','Archive notification templates','Archive eligible notification versions.'),('history','Read notification delivery history','Read paginated redacted delivery outcomes.'),('settings.read','Read notification readiness','Read safe SMTP configuration readiness metadata.')])]
POLICIES=[
('register','Register account','Create a local account.','ACTIVE',1,0,0,'Informational self-service policy; not a role grant.'),
('email.verify','Verify email using valid token','Confirm the account email with a valid token.','ACTIVE',1,1,0,'Informational self-service policy; not a role grant.'),
('email.resend','Resend verification email','Request delivery of a new verification email.','ACTIVE',1,1,0,'Informational self-service policy; not a role grant.'),
('login','Login','Create an authenticated session after credential and verification checks.','ACTIVE',1,0,1,'Informational self-service policy; session and account checks remain authoritative.'),
('password.reset.request','Request password reset','Request a password reset; reset workflow is not implemented.','PLANNED',1,1,1,'Password reset is not implemented; policy values are informational only.'),
('profile.read','View own account','Read the authenticated account profile.','ACTIVE',0,0,1,'Informational self-service policy; authenticated identity is required.'),
('profile.update','Update own account profile','Update the authenticated account profile.','PLANNED',0,0,1,'No approved profile-update endpoint is available.'),
('password.change','Change own password','Change the authenticated account password.','PLANNED',0,0,1,'No approved password-change endpoint is available.'),
('registration.read','View own registration status','Read the authenticated account registration status.','ACTIVE',0,0,1,'Informational self-service policy; authenticated identity is required.'),
('registration.complete','Complete registration profile','Complete the authenticated account registration profile.','ACTIVE',0,0,1,'Informational self-service policy; authenticated identity is required.'),
('registration.submit','Submit registration application','Submit an application only when all conditional verification and consent policies are satisfied.','CONDITIONAL',0,0,0,'Conditional verification and consent policy is not implemented.'),
('security_activity.read','View own security activity','Read security activity for the authenticated account.','PLANNED',0,0,1,'No approved security-activity endpoint is available.'),
('sessions.manage','Manage own sessions','Revoke or otherwise manage the authenticated account sessions.','PLANNED',0,0,1,'Session inventory management is not implemented.'),
('tenant.access','Access Tenant workspace','Access tenant data only with a valid verified session and active tenant membership.','CONDITIONAL',0,0,0,'Tenant access requires valid session, active membership, and tenant-scoped permissions.'),
('users.read','View other user accounts','Cross-user account access is denied by default.','SYSTEM RESTRICTED',0,0,0,'Cross-user account access is denied by default.'),
('platform.access','Access Platform Administration','Platform access requires the explicit database-backed platform permission checks.','CONDITIONAL',0,0,0,'Platform access requires explicit database-backed platform permission checks.')]
DRAFT={'template_code':'EMAIL_VERIFICATION','channel':'EMAIL','locale':'en','status':'DRAFT','subject':'KLOP - Email verification','body':'Complete email verification using this single-use link:\n{{verification_link}}\nThe link expires in {{expiry_hours}} hour(s). Never share it.','requires_actual_approved_actor_for_sql_server':True}
def statements(s):
    buf=''
    for l in s.splitlines(keepends=True):
        buf+=l
        if sqlite3.complete_statement(buf): yield buf;buf=''
    if buf.strip(): raise ValueError('Incomplete SQL statement')
def build(base, output):
    base=pathlib.Path(base); output=pathlib.Path(output)
    if output.exists():raise FileExistsError(output)
    data=(base/'KlopPlatform.db').read_bytes();assert hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()==BASE_BLOB,'Unexpected v1.0 database bytes'
    old=json.loads((base/'schema_definition.json').read_text());shutil.copyfile(base/'KlopPlatform.db',output)
    c=sqlite3.connect(output);c.execute('PRAGMA foreign_keys=ON')
    try:
        c.execute('BEGIN IMMEDIATE')
        # Rebuild only the copied junction table. No existing grant becomes effective: historical mapping records are retained in v1.0 and projected separately in JSON.
        historic=c.execute('SELECT r.Code,p.Code,s.Code FROM mst__RolePermissions m JOIN mst__Roles r ON r.RoleId=m.RoleId JOIN mst__Permissions p ON p.PermissionId=m.PermissionId JOIN mst__RoleScopes s ON s.RoleScopeId=r.RoleScopeId ORDER BY r.Code,p.Code').fetchall()
        c.execute('DROP TABLE mst__RolePermissions')
        for name,obj in old['v1.10_HOLD_not_applied'].items(): c.execute(obj['sql'])
        c.execute('CREATE UNIQUE INDEX UX_RolePermissions_Platform ON mst__RolePermissions(RoleId,PermissionId) WHERE TenantTypeId IS NULL')
        c.execute('CREATE UNIQUE INDEX UX_RolePermissions_Tenant ON mst__RolePermissions(RoleId,PermissionId,TenantTypeId) WHERE TenantTypeId IS NOT NULL')
        c.execute('CREATE INDEX IX_mst__RolePermissions_PermissionId ON mst__RolePermissions(PermissionId)')
        for op in ('INSERT','UPDATE'):
            c.execute(f'''CREATE TRIGGER trg_RolePermissions_ValidateMatrixScope_{op} BEFORE {op} ON mst__RolePermissions WHEN NOT EXISTS(SELECT 1 FROM mst__Roles r JOIN mst__Permissions p ON p.PermissionId=NEW.PermissionId JOIN mst__RoleScopes s ON s.RoleScopeId=r.RoleScopeId WHERE r.RoleId=NEW.RoleId AND r.RoleScopeId=p.RoleScopeId AND ((s.Code='PLATFORM' AND NEW.TenantTypeId IS NULL) OR (s.Code='TENANT' AND NEW.TenantTypeId IS NOT NULL))) BEGIN SELECT RAISE(ABORT,'Incompatible role permission scope'); END;''')
        c.executemany('INSERT INTO mst__PermissionReadinessStatuses(Code,Name,AllowsEffective,AllowsMatrixEdit) VALUES(?,?,?,?)',[('ACTIVE','Active',1,1),('PLANNED','Planned',0,0),('HOLD','Hold',0,0),('CONDITIONAL','Conditional',0,0),('SYSTEM RESTRICTED','System restricted',1,0),('INVALID SCOPE','Invalid scope',0,0)])
        scope=c.execute("SELECT RoleScopeId FROM mst__RoleScopes WHERE Code='PLATFORM'").fetchone()[0]
        c.executemany('INSERT INTO mst__Permissions(RoleScopeId,Code,Name,Description,SortOrder,CreatedAtUtc) VALUES(?,?,?,?,?,?)',[(scope,*p,NOW) for p in PERMISSIONS])
        for pid,code,name,desc,active in c.execute('SELECT PermissionId,Code,Name,Description,IsActive FROM mst__Permissions').fetchall():
            parts=code.split('.',2);module,resource=parts[:2];action=parts[2] if len(parts)>2 else 'unspecified';reason=None
            if code.startswith('platform.notifications.'):
                readiness='HOLD';reason='Notification capability is unassigned and held for owner review; no role grant is implied.'
            elif code in ('platform.role_permissions.read','platform.role_permissions.update','platform.permissions.manage'):
                readiness='SYSTEM RESTRICTED';reason='Essential matrix access; system restricted and not editable through this matrix.'
            elif code in ('platform.config.manage','platform.roles.manage','platform.tenants.manage','platform.verifications.review'):
                readiness='HOLD';reason='Platform Setup capabilities remain on HOLD outside the approved matrix scope.'
            else:readiness='ACTIVE' if active else 'PLANNED';reason=None if active else 'Permission is not ready for activation; matrix changes are disabled.'
            c.execute('INSERT INTO mst__PermissionMatrixMetadata(PermissionId,ModuleCode,ResourceCode,ActionCode,PermissionDescription,ReadinessCode,RestrictionReason,UpdatedAtUtc) VALUES(?,?,?,?,?,?,?,?)',(pid,module,resource,action,desc or name+' capability.',readiness,reason,NOW))
        c.executemany('INSERT INTO mst__AccountSelfServicePolicies(PolicyCode,ModuleCode,ResourceCode,ActionCode,Name,Description,ReadinessCode,PublicAllowed,UnverifiedAllowed,VerifiedAllowed,RestrictionReason,SortOrder,UpdatedAtUtc) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)',[('account.self_service.'+p[0],'account','self_service',p[0],*p[1:],800+i,NOW) for i,p in enumerate(POLICIES)])
        for stmt in statements((ROOT/'notification_schema.sql').read_text()):c.execute(stmt)
        c.executemany('INSERT INTO ntf__NotificationChannelStatuses VALUES(?,?,?)',[('CONFIGURATION_REQUIRED','Configuration required',0),('READY','Ready',1),('DISABLED','Disabled',0)])
        c.executemany('INSERT INTO ntf__NotificationTemplateStatuses VALUES(?,?,?)',[('DRAFT','Draft',0),('PENDING_APPROVAL','Pending approval',0),('APPROVED','Approved',0),('ACTIVE','Active',0),('ARCHIVED','Archived',1)])
        c.executemany('INSERT INTO ntf__NotificationDeliveryOutcomes VALUES(?,?)',[('PROVIDER_ACCEPTED','Provider accepted; inbox delivery is not confirmed'),('PROVIDER_REJECTED','Provider rejected')])
        c.executemany('INSERT INTO ntf__NotificationErrorCategories VALUES(?,?)',[('SMTP_FAILURE','SMTP provider failure'),('SMTP_CONFIGURATION','SMTP configuration failure'),('TEMPLATE_UNAVAILABLE','Active verification template unavailable')])
        c.execute("INSERT INTO ntf__NotificationTemplateTypes VALUES('EMAIL_VERIFICATION','Email verification',1)")
        c.execute("INSERT INTO ntf__NotificationChannels(ChannelCode,DisplayName,IsEnabled,StatusCode) VALUES('EMAIL','Email',1,'CONFIGURATION_REQUIRED')")
        c.executemany('INSERT INTO ntf__NotificationVariableDefinitions VALUES(?,?,?,?,?)',[('EMAIL_VERIFICATION','verification_link','Verification link','HTTPS_URL',1),('EMAIL_VERIFICATION','expiry_hours','Link expiry hours','INTEGER',1)])
        for key in ('notification.email_verification_templates.enabled','notification.email_verification_delivery_audit.enabled'):
            c.execute("INSERT INTO cfg__SystemConfigurations(ConfigurationKey,ConfigurationValue,ValueType,Category,IsSystem,IsEditable,RequiresApproval,CreatedAtUtc) VALUES(?,'false','BOOLEAN','Notifications',1,0,1,?)",(key,NOW))
        # No fake seed actor, business records or grants in saved working database. Source projection of proposed mappings retained outside database.
        proposed=[{'role':r,'permission':p,'tenant_type':t,'source':'v1.1 historical seed; v1.10/003 contextualization'} for r,p,s in historic for t in ([None] if s=='PLATFORM' else ['PERSONAL','ORGANIZATION'])]
        for code,*_ in PERMISSIONS:
            roles=[]
            if code.startswith('platform.legal_documents.'):roles=['SUPER_ADMIN']+(['PLATFORM_SUPPORT'] if code.rsplit('.',1)[-1] in ('read','create','edit','preview') else [])
            elif code=='platform.registrations.read':roles=['SUPER_ADMIN','PLATFORM_SUPPORT']
            elif code.startswith('platform.role_permissions.'):roles=['SUPER_ADMIN']
            for role in roles:proposed.append({'role':role,'permission':code,'tenant_type':None,'source':'versioned SQL proposal (not applied)'})
        for key,val in {'studio_version':'1.1','source_commit':SOURCE,'status':'OFFLINE PROPOSAL / NOT LIVE / NOT FROZEN','rbac':'Structure projected; role grants deliberately empty; proposals in seed_projection.json; notification HOLD','config':'20 inherited placeholders + 2 explicit default-off flags; no real values','migration':'No SQL Server execution; v1.10 and v1.11 remain HOLD'}.items():c.execute('UPDATE studio__Metadata SET Value=? WHERE Key=?',(val,key))
        for name in old['v1.10_HOLD_not_applied']:
            c.execute('INSERT OR REPLACE INTO studio__SourceObjects VALUES(?,?,?,?)',(name,name.replace('.','__'),'v1.10','OFFLINE PROJECTION / SQL HOLD'))
        for (name,) in c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'ntf__%'").fetchall():c.execute('INSERT INTO studio__SourceObjects VALUES(?,?,?,?)',(name.replace('__','.'),name,'v1.11','OFFLINE PROJECTION / SQL HOLD'))
        c.execute('INSERT INTO studio__ChangeLog(Version,Summary,ChangedAtUtc) VALUES(?,?,?)',('1.1','Project reviewed v1.10 RBAC and v1.11 Notification schema; keep grants unassigned, no actors, default-off flags',NOW))
        assert c.execute('PRAGMA integrity_check').fetchall()==[('ok',)] and not c.execute('PRAGMA foreign_key_check').fetchall()
        c.commit()
        return {'source_commit':SOURCE,'historical_grants':len(historic),'projected_grants_not_applied':proposed,'draft_recipe_not_applied':DRAFT,'reason':'SQL HOLD; do not infer live grants or actual seed actor; legacy and prepared grants are comparison data only.'}
    except Exception:c.rollback();raise
    finally:c.close()
def schema(db):
    c=sqlite3.connect(db)
    try:return {'source_commit':SOURCE,'studio_version':'1.1','status':'SQL HOLD / OFFLINE ONLY','objects':[{'type':t,'name':n,'table':tbl,'sqlite_sql':s} for t,n,tbl,s in c.execute("SELECT type,name,tbl_name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY type,name")],'limitations':['ROWVERSION BLOB placeholder, no native SQL Server concurrency','SQLite UUID text/default differs from SQL Server','No SQL Server stored procedures, collation or grant semantics','Earlier v1.0 projection remains partial; no live introspection']}
    finally:c.close()
if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--base',type=pathlib.Path,default=ROOT.parent);ap.add_argument('--output',type=pathlib.Path,default=ROOT/'KlopPlatform.db');args=ap.parse_args();seed=build(args.base,args.output);(args.output.parent/'seed_projection.json').write_text(json.dumps(seed,indent=2)+'\n');(args.output.parent/'schema_definition.json').write_text(json.dumps(schema(args.output),indent=2)+'\n')
