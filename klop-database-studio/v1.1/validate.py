"""Validate a v1.1 snapshot without changing its bytes. Fixtures live only in memory."""
import argparse, hashlib, json, pathlib, sqlite3
ROOT=pathlib.Path(__file__).resolve().parent

def validate(db):
    db=pathlib.Path(db).resolve(); before=hashlib.sha256(db.read_bytes()).hexdigest()
    src=sqlite3.connect(db.as_uri()+'?mode=ro',uri=True); src.execute('PRAGMA foreign_keys=ON'); c=sqlite3.connect(':memory:'); src.backup(c); src.close(); c.execute('PRAGMA foreign_keys=ON')
    results={}
    def check(name,value):
        assert value, name;results[name]='PASS'
    def rejects(name,sql,args=()):
        try:c.execute(sql,args)
        except sqlite3.IntegrityError:results[name]='PASS (rejected)'
        else:raise AssertionError(name+' unexpectedly accepted')
    def one(s,args=()):return c.execute(s,args).fetchone()[0]
    try:
        counts={n:one('SELECT COUNT(*) FROM "'+n+'"') for (n,) in c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name").fetchall()}
        check('integrity_check',c.execute('PRAGMA integrity_check').fetchall()==[('ok',)])
        check('foreign_key_check',not c.execute('PRAGMA foreign_key_check').fetchall())
        check('table_inventory',len(counts)==63 and sum(n.startswith('ntf__') for n in counts)==13 and sum(n.startswith('studio__') for n in counts)==3)
        check('permission_metadata_complete',counts['mst__Permissions']==counts['mst__PermissionMatrixMetadata']==37)
        check('notification_permissions_hold',one("SELECT COUNT(*) FROM mst__Permissions p JOIN mst__PermissionMatrixMetadata m ON p.PermissionId=m.PermissionId JOIN mst__PermissionReadinessStatuses r ON m.ReadinessCode=r.Code WHERE p.Code LIKE 'platform.notifications.%' AND r.Code='HOLD' AND r.AllowsEffective=0 AND r.AllowsMatrixEdit=0")==10)
        check('role_grants_unassigned',counts['mst__RolePermissions']==0 and counts['iam__PlatformRoleAssignments']==counts['iam__TenantRoleAssignments']==0)
        check('account_policies_separate',counts['mst__AccountSelfServicePolicies']==16 and one("SELECT COUNT(*) FROM mst__Permissions WHERE Code LIKE 'account.%'")==0)
        check('flags_default_off',one("SELECT COUNT(*) FROM cfg__SystemConfigurations WHERE ConfigurationKey IN ('notification.email_verification_templates.enabled','notification.email_verification_delivery_audit.enabled') AND ConfigurationValue='false' AND IsActive=1 AND ValueType='BOOLEAN' AND StorageType='PLAIN' AND RequiresApproval=1")==2)
        check('no_real_configuration',one("SELECT COUNT(*) FROM cfg__SystemConfigurations WHERE ConfigurationKey NOT LIKE 'notification.%' AND (ConfigurationValue IS NOT NULL OR DefaultValue IS NOT NULL OR IsActive<>0)")==0 and counts['cfg__SystemConfigurations']==22)
        check('no_business_records',all(n==0 for t,n in counts.items() if t.startswith(('iam__','ten__','reg__','leg__','aud__'))) and all(counts[t]==0 for t in ('ntf__NotificationTemplates','ntf__NotificationTemplateVersions','ntf__NotificationTemplateApprovals','ntf__NotificationTemplateVersionVariables','ntf__NotificationDeliveries','ntf__NotificationDeliveryAttempts')))
        check('email_only_not_operational',c.execute('SELECT ChannelCode,IsEnabled,StatusCode FROM ntf__NotificationChannels').fetchall()==[('EMAIL',1,'CONFIGURATION_REQUIRED')])
        check('no_recipient_metadata',not any('recipient' in r[1].lower() for r in c.execute('PRAGMA table_info(ntf__NotificationDeliveries)')))
        # Isolated constraint tests. All writes are made only to the in-memory copy and rolled back.
        c.execute('BEGIN')
        role=one("SELECT RoleId FROM mst__Roles WHERE Code='SUPER_ADMIN'"); tenantrole=one("SELECT RoleId FROM mst__Roles WHERE Code='OWNER'"); platform=one("SELECT PermissionId FROM mst__Permissions WHERE Code='platform.registrations.read'"); tenantperm=one("SELECT PermissionId FROM mst__Permissions WHERE Code='tenant.read'"); personal=one("SELECT TenantTypeId FROM mst__TenantTypes WHERE Code='PERSONAL'");org=one("SELECT TenantTypeId FROM mst__TenantTypes WHERE Code='ORGANIZATION'")
        mapping='INSERT INTO mst__RolePermissions(RoleId,PermissionId,TenantTypeId) VALUES(?,?,?)'
        rejects('scope_mismatch',mapping,(role,tenantperm,None));rejects('platform_requires_null_tenant',mapping,(role,platform,personal));rejects('tenant_requires_context',mapping,(tenantrole,tenantperm,None));rejects('invalid_tenant_fk',mapping,(tenantrole,tenantperm,999999))
        c.execute(mapping,(role,platform,None));rejects('platform_null_unique',mapping,(role,platform,None));c.execute(mapping,(tenantrole,tenantperm,personal));c.execute(mapping,(tenantrole,tenantperm,org));rejects('tenant_context_unique',mapping,(tenantrole,tenantperm,org));check('tenant_context_separate',one('SELECT COUNT(*) FROM mst__RolePermissions WHERE RoleId=? AND PermissionId=?',(tenantrole,tenantperm))==2)
        channel=one("SELECT ChannelId FROM ntf__NotificationChannels WHERE ChannelCode='EMAIL'"); template="INSERT INTO ntf__NotificationTemplates(TemplateId,TemplateCode,DisplayName,ChannelId,LocaleCode,CreatedByUserId) VALUES(?,?,?,?,?,?)"
        rejects('actor_fk',template,('fixture-template','EMAIL_VERIFICATION','Fixture',channel,'en',999999))
        actor=c.execute("INSERT INTO iam__Users(Email,NormalizedEmail,DisplayName) VALUES('studio-fixture@example.invalid','STUDIO-FIXTURE@EXAMPLE.INVALID','OFFLINE FIXTURE')").lastrowid
        c.execute(template,('fixture-template','EMAIL_VERIFICATION','Fixture',channel,'en',actor));rejects('template_key_unique',template,('fixture-duplicate','EMAIL_VERIFICATION','Fixture',channel,'en',actor))
        draft=json.loads((ROOT/'seed_projection.json').read_text())['draft_recipe_not_applied']; version='INSERT INTO ntf__NotificationTemplateVersions(TemplateVersionId,TemplateId,TemplateCode,VersionNumber,StatusCode,Subject,Body,CreatedByUserId) VALUES(?,?,?,?,?,?,?,?)'
        args=('fixture-v1','fixture-template','EMAIL_VERIFICATION',1,'DRAFT',draft['subject'],draft['body'],actor)
        c.execute(version,args); rejects('version_positive',version,('fixture-bad','fixture-template','EMAIL_VERIFICATION',0,'DRAFT','x','x',actor));rejects('version_number_unique',version,('fixture-dup','fixture-template','EMAIL_VERIFICATION',1,'DRAFT','x','x',actor))
        c.execute("INSERT INTO ntf__NotificationTemplateTypes VALUES('OFFLINE_FIXTURE_OTHER','Fixture',0)")
        c.execute("INSERT INTO ntf__NotificationVariableDefinitions VALUES('OFFLINE_FIXTURE_OTHER','foreign_var','Fixture','STRING',1)")
        rejects('version_template_composite_fk',version,('fixture-wrong-type','fixture-template','OFFLINE_FIXTURE_OTHER',2,'DRAFT','x','x',actor))
        var='INSERT INTO ntf__NotificationTemplateVersionVariables VALUES(?,?,?,?)'
        rejects('variable_definition_fk',var,('fixture-v1','EMAIL_VERIFICATION','unknown',1));rejects('variable_type_composite_fk',var,('fixture-v1','OFFLINE_FIXTURE_OTHER','foreign_var',1))
        for v in ('verification_link','expiry_hours'):c.execute(var,('fixture-v1','EMAIL_VERIFICATION',v,1))
        check('draft_recipe_required_variables',all('{{'+v+'}}' in draft['body'] for v in ('verification_link','expiry_hours')) and '{{verification_link}}' not in draft['subject'])
        c.execute("UPDATE ntf__NotificationTemplateVersions SET StatusCode='PENDING_APPROVAL',SubmittedAtUtc='2026-11-28T00:00:00Z' WHERE TemplateVersionId='fixture-v1'")
        rejects('approval_decision_check',"INSERT INTO ntf__NotificationTemplateApprovals(TemplateVersionId,ActorUserId,DecisionCode) VALUES('fixture-v1',?,'MAYBE')",(actor,))
        c.execute("INSERT INTO ntf__NotificationTemplateApprovals(TemplateVersionId,ActorUserId,DecisionCode) VALUES('fixture-v1',?,'REJECT')",(actor,));c.execute("UPDATE ntf__NotificationTemplateVersions SET StatusCode='DRAFT' WHERE TemplateVersionId='fixture-v1'")
        c.execute("UPDATE ntf__NotificationTemplateVersions SET StatusCode='PENDING_APPROVAL' WHERE TemplateVersionId='fixture-v1'");c.execute("INSERT INTO ntf__NotificationTemplateApprovals(TemplateVersionId,ActorUserId,DecisionCode) VALUES('fixture-v1',?,'APPROVE')",(actor,));c.execute("UPDATE ntf__NotificationTemplateVersions SET StatusCode='APPROVED' WHERE TemplateVersionId='fixture-v1'");c.execute("UPDATE ntf__NotificationTemplateVersions SET StatusCode='ACTIVE',ActivatedAtUtc='2026-11-28T00:01:00Z' WHERE TemplateVersionId='fixture-v1'")
        rejects('active_immutable',"UPDATE ntf__NotificationTemplateVersions SET Body='modified' WHERE TemplateVersionId='fixture-v1'");rejects('active_delete',"DELETE FROM ntf__NotificationTemplateVersions WHERE TemplateVersionId='fixture-v1'");rejects('active_null_activation_timestamp',"UPDATE ntf__NotificationTemplateVersions SET ActivatedAtUtc=NULL WHERE TemplateVersionId='fixture-v1'")
        c.execute(version,('fixture-v2','fixture-template','EMAIL_VERIFICATION',2,'APPROVED',draft['subject'],draft['body'],actor))
        rejects('single_active_version',"UPDATE ntf__NotificationTemplateVersions SET StatusCode='ACTIVE' WHERE TemplateVersionId='fixture-v2'");c.execute('SAVEPOINT activate')
        c.execute("UPDATE ntf__NotificationTemplateVersions SET StatusCode='ARCHIVED',ArchivedAtUtc='2026-11-28T00:02:00Z' WHERE TemplateVersionId='fixture-v1'");c.execute("UPDATE ntf__NotificationTemplateVersions SET StatusCode='ACTIVE',ActivatedAtUtc='2026-11-28T00:02:00Z' WHERE TemplateVersionId='fixture-v2'")
        check('activation_fixture_single_active',one("SELECT COUNT(*) FROM ntf__NotificationTemplateVersions WHERE StatusCode='ACTIVE'")==1)
        rejects('archived_immutable',"UPDATE ntf__NotificationTemplateVersions SET Subject='modified' WHERE TemplateVersionId='fixture-v1'");rejects('archived_delete',"DELETE FROM ntf__NotificationTemplateVersions WHERE TemplateVersionId='fixture-v1'")
        c.execute('ROLLBACK TO activate');c.execute('RELEASE activate');check('activation_rollback',one("SELECT StatusCode FROM ntf__NotificationTemplateVersions WHERE TemplateVersionId='fixture-v1'")=='ACTIVE')
        delivery='INSERT INTO ntf__NotificationDeliveries(DeliveryId,TemplateVersionId,TemplateCodeSnapshot,TemplateVersionSnapshot,ChannelId,CorrelationId) VALUES(?,?,?,?,?,?)'
        c.execute(delivery,('fixture-delivery','fixture-v1','EMAIL_VERIFICATION',1,channel,'fixture-correlation'));rejects('delivery_snapshot_positive',delivery,('fixture-bad-delivery','fixture-v1','EMAIL_VERIFICATION',0,channel,'fixture-correlation'))
        attempt='INSERT INTO ntf__NotificationDeliveryAttempts(DeliveryId,AttemptNumber,OutcomeCode,ErrorCategoryCode,ProviderAccepted) VALUES(?,?,?,?,?)';rejects('attempt_positive',attempt,('fixture-delivery',0,'PROVIDER_ACCEPTED',None,1));rejects('accepted_requires_no_error',attempt,('fixture-delivery',1,'PROVIDER_ACCEPTED','SMTP_FAILURE',1));rejects('rejected_requires_error',attempt,('fixture-delivery',1,'PROVIDER_REJECTED',None,0));rejects('unknown_outcome',attempt,('fixture-delivery',1,'OTHER',None,1));c.execute(attempt,('fixture-delivery',1,'PROVIDER_ACCEPTED',None,1));rejects('attempt_unique',attempt,('fixture-delivery',1,'PROVIDER_REJECTED','SMTP_FAILURE',0));c.execute(attempt,('fixture-delivery',2,'PROVIDER_REJECTED','SMTP_FAILURE',0))
        check('fixture_integrity',c.execute('PRAGMA integrity_check').fetchall()==[('ok',)] and not c.execute('PRAGMA foreign_key_check').fetchall());c.rollback();check('fixture_rollback',one('SELECT COUNT(*) FROM iam__Users')==0 and one('SELECT COUNT(*) FROM ntf__NotificationTemplateVersions')==0 and one('SELECT COUNT(*) FROM mst__RolePermissions')==0)
        check('database_bytes_unchanged',hashlib.sha256(db.read_bytes()).hexdigest()==before)
        return {'status':'PASS — SQLite offline constraints only; not SQL Server procedure validation','source_commit':one("SELECT Value FROM studio__Metadata WHERE Key='source_commit'"),'sha256':before,'domain_tables':60,'studio_tables':3,'checks_passed':len(results),'checks':results,'row_counts':counts,'sqlite_version':sqlite3.sqlite_version,'limitations':['Lifecycle fixture uses explicit SQL state changes, not actual stored procedures or authorization tests.','No SQL Server, SMTP, deployment or live integration.','No real seed actor or role grants persisted.']}
    finally:c.close()
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--db',default=ROOT/'KlopPlatform.db');p.add_argument('--report',type=pathlib.Path);a=p.parse_args();r=validate(a.db);s=json.dumps(r,indent=2)+'\n';print(s);a.report and a.report.write_text(s)
