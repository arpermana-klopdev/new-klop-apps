# Legacy Password Compatibility Fix Report

## Ringkasan

Verifikasi hash legacy yang telah ditentukan kini didukung tanpa mengubah hash tersimpan. Format writer current tetap satu-satunya format pembuatan hash baru. Tidak ada perubahan route, DTO, role/permission, lockout, audit flow, stored procedure mapping, atau perilaku JWT/session.

## Referensi dan bukti spesifikasi legacy

Spesifikasi implementasi yang diberikan untuk pekerjaan ini merujuk ke:

- Repository: `arpermana-klopdev/KLOP.PLATFORM`
- File: `src/KLP.PORTAL.INFRASTRUCTURE/Security/Pbkdf2PasswordHasher.cs`
- Commit: `2d1b850f61947ad36319a6b4639656498076ce7f`
- Algorithm: PBKDF2-HMAC-SHA256
- Parameter: 100,000 iterasi, salt 16 byte, digest 32 byte
- Encoding: `100000.{saltBase64}.{digestBase64}`
- Digest comparison: constant-time

Spesifikasi dibatasi hanya ke format/parameter di atas; tidak ada fallback ke varian legacy lain. Lookup konten GitHub pada commit tersebut dalam sesi ini menghasilkan 404, jadi bukti lokal yang dapat dieksekusi adalah deterministic synthetic fixture yang disediakan dalam task dan lulus test. Fixture bukan credential akun Development.

## File yang diubah

- `src/KLOP.Platform.Application/Features/Security.cs`
  - Mempertahankan writer current `pbkdf2-sha256$rounds$salt$digest` pada 600,000 iterasi, salt acak 32 byte, dan digest 32 byte.
  - Memverifikasi current format dengan batas iterasi 100,000–1,500,000, salt/digest 32 byte, prefix lowercase yang persis, dan Base64 kanonis.
  - Memverifikasi hanya legacy format `100000.{saltBase64}.{digestBase64}` dengan salt 16 byte dan digest 32 byte.
  - Kedua format memakai PBKDF2-HMAC-SHA256 dan `CryptographicOperations.FixedTimeEquals`. Input malformed, non-kanonis, unknown, atau di luar batas ditolak sebelum KDF.
- `tests/KLOP.Platform.UnitTests/Authentication/SecurityTests.cs`
  - Menambahkan deterministic fixture dan kasus positif/negatif parsing/format.
- `tests/KLOP.Platform.UnitTests/Authentication/AuthenticationServiceTests.cs`
  - Menambahkan pengujian login service yang menerima hash fixture legacy melalui `PasswordCodec` yang sama.
- `LEGACY_PASSWORD_COMPATIBILITY_FIX_REPORT.md`
  - Laporan ini.

## Hasil deterministic fixture dan regression tests

Fixture yang diminta berhasil diverifikasi untuk password yang benar; password yang salah ditolak. Test mencakup juga current password benar/salah, iterasi invalid, Base64 invalid/non-kanonis, panjang salt/digest invalid, algorithm unsupported, hash kosong/null, separator tidak terduga, dan perbedaan prefix uppercase/lowercase. Password writer current tetap teruji melalui round-trip existing.

- `dotnet build KLOP.Platform.sln`: **PASS**
- `KLOP.Platform.UnitTests`: **33 passed, 0 failed, 0 skipped**
- Termasuk password codec regression, authentication service regression, API route/OpenAPI contract regression.
- SQL integration tests tidak dijalankan; tidak ada test yang membutuhkan SQL Server dalam verifikasi ini.

## Authentication flow yang ditinjau

`AuthenticationService.Login` tetap melakukan credential lookup melalui `GetLoginCandidate`, memanggil `PasswordCodec.Verify`, kemudian menegakkan status aktif, email verified, dan lockout sebelum membuat session. Password salah untuk kandidat yang ditemukan tetap mencatat login failure; akun tidak eligible tidak membuat session. Hash legacy hanya mengubah hasil verifikasi password yang dikenali dan tidak mengubah session/JWT behavior. Test service legacy memastikan session dibuat untuk kandidat fixture valid; regression tests existing tetap lulus untuk failure, eligibility, dan current-format login.

## Database dan perubahan data

Read-only pemeriksaan konfigurasi Development menunjukkan `Sql:Database` di `src/KLOP.Platform.Api/appsettings.Development.json` adalah `KlopPlatformDB`; `SqlConnectionFactory` menggunakan nilai tersebut sebagai `InitialCatalog`. Tidak ada koneksi/query database dilakukan untuk tugas ini. Environment variables atau konfigurasi runtime lain dapat override file tersebut, sehingga database efektif dari proses yang sedang berjalan tidak dibuktikan melalui koneksi.

**Konfirmasi:** tidak ada perubahan database, schema, user, password hash, atau konfigurasi Production. Tidak ada login E2E otomatis atau SQL mutation test.

## Status SQL runtime dan rekomendasi least privilege

Berdasarkan temuan audit sebelumnya yang disampaikan untuk task ini, identitas SQL runtime mempunyai `sysadmin`, sedangkan `klop_app_runtime` belum mempunyai membership/grants yang memadai. Status tersebut **belum diverifikasi ulang terhadap database** karena tidak ada akses/query database. Ini tetap blocker dan tidak dianggap selesai. Jangan jalankan login manual sebelum DBA mengonfirmasi principal runtime yang disetujui dan hak akses efektifnya.

Rekomendasi: gunakan principal khusus runtime aplikasi yang bukan `sysadmin`; petakan hanya ke database aplikasi; berikan `EXECUTE` per stored procedure di bawah melalui role/user runtime yang telah disetujui DBA. Jangan memberikan direct table access, `db_owner`, `CONTROL`, atau schema-wide `EXECUTE` bila tidak diperlukan. Terapkan ownership chaining/module signing sesuai kebijakan DBA bila prosedur membutuhkan akses tabel internal. Matriks berikut adalah rekomendasi cakupan, bukan grant yang telah diterapkan.

| Schema | Stored procedure | Alur aplikasi | Izin runtime yang direkomendasikan |
|---|---|---|---|
| `iam` | `usp_RegisterLocalUser` | Registrasi | `EXECUTE` |
| `iam` | `usp_ConfirmEmail` | Konfirmasi email | `EXECUTE` |
| `iam` | `usp_IssueEmailVerificationChallenge` | Kirim ulang verifikasi | `EXECUTE` |
| `iam` | `usp_GetLocalLoginCandidate` | Lookup kredensial/login | `EXECUTE` |
| `iam` | `usp_RecordLocalLoginFailure` | Pencatatan kegagalan login | `EXECUTE` |
| `iam` | `usp_CreateAuthSession` | Membuat session | `EXECUTE` |
| `iam` | `usp_ValidateSessionAccess` | Validasi akses/session | `EXECUTE` |
| `iam` | `usp_RotateRefreshToken` | Refresh session/token | `EXECUTE` |
| `iam` | `usp_RevokeAuthSession` | Logout/revoke session | `EXECUTE` |
| `iam` | `usp_GetUserProfile` | Membaca profil | `EXECUTE` |
| `iam` | `usp_AssignTenantRole` | Assign tenant role | `EXECUTE` |
| `iam` | `usp_RevokeTenantRole` | Revoke tenant role | `EXECUTE` |
| `cfg` | `usp_Configuration_GetByKey` | Runtime settings/readiness/configuration | `EXECUTE` |
| `mst` | `usp_OrganizationType_GetAll` | Master data organization type | `EXECUTE` |
| `mst` | `usp_TenantType_GetAll` | Master data tenant type | `EXECUTE` |
| `ten` | `usp_ListMyTenants` | Daftar tenant user | `EXECUTE` |
| `ten` | `usp_CreateTenantWithOwner` | Membuat tenant | `EXECUTE` |
| `ten` | `usp_InviteExistingUser` | Undangan tenant | `EXECUTE` |
| `ten` | `usp_AcceptMembership` | Menerima membership | `EXECUTE` |
| `ten` | `usp_RemoveTenantMember` | Menghapus membership | `EXECUTE` |

Tidak ada `CREATE LOGIN`, `ALTER ROLE`, `GRANT`, atau perubahan keamanan database yang dijalankan. Perubahan akses memerlukan persetujuan dan eksekusi DBA.

## Panduan manual login terkontrol

Setelah DBA menyediakan serta mengonfirmasi identitas runtime least-privilege dan konfigurasi efektif menunjuk `KlopPlatformDB`, lakukan pengujian manual melalui client Development yang disetujui pada route `/api/v1/auth/login` dengan salah satu akun existing:

- `super.admin@klop-test.example`
- `platform.support@klop-test.example`

Operator yang berwenang memasukkan password melalui kanal yang disetujui. Jangan menaruh password/token di source, laporan, shell history, log, atau tiket; jangan bagikan response token. Konfirmasi hasil login/session hanya di client yang aman. Tidak ada kredensial yang diketahui atau digunakan oleh task ini.

## Blocker tersisa

1. DBA harus menyetujui dan menyiapkan identitas SQL runtime dengan hak minimum; temuan `sysadmin` sebelumnya belum diselesaikan/diverifikasi.
2. Konfigurasi efektif saat proses dijalankan perlu dikonfirmasi secara aman, karena environment/runtime overrides tidak diverifikasi.
3. Manual login kedua akun di atas belum dilakukan dan tetap menunggu blocker SQL/runtime diselesaikan.
4. Konten sumber legacy GitHub tidak berhasil diambil pada commit yang dirujuk (404); cakupan verifikasi ini karenanya dibatasi pada spesifikasi yang diberikan dan fixture deterministik yang telah lulus.
