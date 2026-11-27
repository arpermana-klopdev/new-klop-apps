"""Non-executable SQL text sanity checks only, NOT a SQL Server parser/integration test."""
from pathlib import Path
import re
p=Path(__file__).resolve().parent.parent
sql=p/'sql'/'01_StoredProcedures'
files=sorted(sql.glob('*.sql'))
blocks=[]
for f in files:
    txt=f.read_text(encoding='utf-8')
    assert txt.count("CREATE OR ALTER PROCEDURE ") >= 1, f
    assert not re.search(r'@Resource\s*=\s*CONCAT\(', txt), f'Unsupported expression EXEC argument: {f}'
    parts=re.split(r'(?im)^CREATE OR ALTER PROCEDURE\s+', txt)[1:]
    for piece in parts:
        name=re.match(r'([\w]+\.[\w]+)',piece).group(1)
        proc=piece.split('\nGO',1)[0]
        assert 'BEGIN TRY' in proc and 'BEGIN CATCH' in proc and 'BEGIN TRANSACTION' in proc
        assert 'INSERT INTO aud.AuditEvents' in proc, name
        assert 'COMMIT TRANSACTION' in proc and 'ROLLBACK TRANSACTION' in proc, name
        assert 'SET XACT_ABORT ON' in proc, name
        if 'sp_getapplock' in proc:
            assert '@LockResource' in proc and '@Resource=@LockResource' in proc
            assert 'KLOP/TENANT/' in proc
        blocks.append((name, proc))
expected={'iam.usp_RegisterLocalUser','iam.usp_ConfirmEmail','ten.usp_CreateTenantWithOwner',
          'ten.usp_InviteExistingUser','ten.usp_AcceptMembership','ten.usp_RemoveTenantMember',
          'iam.usp_AssignTenantRole','iam.usp_RevokeTenantRole'}
assert {x[0] for x in blocks}==expected
assert len(blocks)==8
assert len([x for x in blocks if 'sp_getapplock' in x[1]])==5
assert not any(re.search(r'(?im)^\s*\b(ALTER|UPDATE|DELETE|INSERT)\b\s+(?:TABLE\s+)?(?:mst|cfg)\.', s) for _,s in blocks)
print('STATIC PASS: 8 procedures, 8 audit inserts, 5 tenant locks, no master/config writes')
print('LIMIT: No live SQL Server compilation, execution, concurrency or privilege validation')
