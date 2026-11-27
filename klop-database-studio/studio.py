"""Local-only utility; inspection, backup, and validated SQL transactions for working SQLite."""
import argparse, datetime, json, pathlib, sqlite3, shutil
ROOT=pathlib.Path(__file__).resolve().parent

def connect(db,readonly=False):
    p=pathlib.Path(db).resolve()
    if not p.is_file(): raise SystemExit(f'Database not found: {p}')
    c=sqlite3.connect(p.as_uri()+'?mode='+('ro' if readonly else 'rw'),uri=True)
    c.execute('PRAGMA foreign_keys=ON')
    if c.execute("SELECT Value FROM studio__Metadata WHERE Key='studio_version'").fetchone() is None:
        raise SystemExit('Not a KLOP Studio database')
    return c

def validate(c):
    i=c.execute('PRAGMA integrity_check').fetchall();fk=c.execute('PRAGMA foreign_key_check').fetchall()
    return {'integrity':i,'foreign_key_violations':fk,'pass':i==[('ok',)] and not fk}

def backup(c,p):
    p=pathlib.Path(p)
    if p.exists():raise SystemExit(f'Backup already exists: {p}')
    p.parent.mkdir(parents=True,exist_ok=True)
    with sqlite3.connect(p) as dst:c.backup(dst)
    return p

def dump(c):
    return {n:c.execute('SELECT count(*) FROM "'+n.replace('"','""')+'"').fetchone()[0] for (n,) in c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")}

def statements(text):
    buf=''
    for ch in text:
        buf+=ch
        if ch==';' and sqlite3.complete_statement(buf):yield buf.strip();buf=''
    if buf.strip():raise ValueError('SQL file must end statements with semicolons')

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--db',default=str(ROOT/'KlopPlatform.db'));sp=p.add_subparsers(dest='command',required=True)
    sp.add_parser('inspect');sp.add_parser('validate');b=sp.add_parser('backup');b.add_argument('destination');a=sp.add_parser('apply');a.add_argument('sql_file');a.add_argument('--version',required=True);a.add_argument('--summary',required=True);a.add_argument('--confirm-working-db',action='store_true')
    args=p.parse_args();c=connect(args.db,readonly=args.command in ('inspect','validate','backup'))
    try:
        if args.command=='inspect':print(json.dumps({'metadata':dict(c.execute('SELECT Key,Value FROM studio__Metadata')),'counts':dump(c)},indent=2))
        elif args.command=='validate':
            r=validate(c);print(json.dumps(r,indent=2));return 0 if r['pass'] else 1
        elif args.command=='backup':print(backup(c,args.destination))
        else:
            if not args.confirm_working_db:raise SystemExit('Explicit --confirm-working-db required. SQL must be SQLite, not T-SQL.')
            # Disallow attach, extension load, disabling integrity or altering Studio metadata during user SQL.
            def authorize(op,arg1,arg2,db,src):
                if op in (sqlite3.SQLITE_ATTACH,sqlite3.SQLITE_DETACH,sqlite3.SQLITE_PRAGMA,sqlite3.SQLITE_TRANSACTION,sqlite3.SQLITE_SAVEPOINT):return sqlite3.SQLITE_DENY
                if op==sqlite3.SQLITE_FUNCTION and (arg2 or '').lower()=='load_extension':return sqlite3.SQLITE_DENY
                if op in (sqlite3.SQLITE_INSERT,sqlite3.SQLITE_UPDATE,sqlite3.SQLITE_DELETE,sqlite3.SQLITE_DROP_TABLE,sqlite3.SQLITE_ALTER_TABLE,sqlite3.SQLITE_DROP_INDEX) and any((x or '').startswith('studio__') for x in (arg1,arg2)):return sqlite3.SQLITE_DENY
                return sqlite3.SQLITE_OK
            stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ');bak=backup(c,pathlib.Path(args.db).with_suffix('.'+stamp+'.bak.db'))
            c.execute('BEGIN IMMEDIATE');c.set_authorizer(authorize)
            try:
                for stmt in statements(pathlib.Path(args.sql_file).read_text(encoding='utf-8')):c.execute(stmt)
                c.set_authorizer(None);r=validate(c)
                if not r['pass']:raise ValueError(f'Validation failed: {r}')
                c.execute('INSERT INTO studio__ChangeLog(Version,Summary) VALUES (?,?)',(args.version,args.summary));c.execute("UPDATE studio__Metadata SET Value=? WHERE Key='studio_version'",(args.version,));c.commit();print(json.dumps({'status':'applied','backup':str(bak),'validation':r},indent=2))
            except Exception:c.set_authorizer(None);c.rollback();raise
    finally:c.close()
    return 0
if __name__=='__main__':raise SystemExit(main())
