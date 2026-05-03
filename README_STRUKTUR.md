# MySimtek Teknisi - Flutter App

Aplikasi mobile untuk teknisi MySimtek dengan fitur login dan dashboard.

## Struktur Proyek

```
lib/
├── main.dart                           # Entry point aplikasi
├── app.dart                           # Root widget dengan splash screen
├── core/
│   ├── constants/
│   │   ├── api_constants.dart        # Endpoint API untuk teknisi
│   │   ├── app_colors.dart           # Warna tema aplikasi
│   │   └── app_version.dart          # Versi aplikasi
│   ├── models/
│   │   └── user_model.dart           # Model data user
│   ├── services/
│   │   ├── api_service.dart          # Service untuk API calls
│   │   └── storage_service.dart      # Local storage (SharedPreferences)
│   └── providers/
│       └── auth_provider.dart        # State management untuk autentikasi
└── features/
    ├── auth/
    │   └── screens/
    │       └── login_screen.dart     # Halaman login teknisi
    └── teknisi/
        └── screens/
            ├── teknisi_shell.dart    # Bottom navigation container
            ├── beranda_screen.dart   # Tab Beranda (Home)
            └── akun_screen.dart      # Tab Akun (Profile)
```

## Fitur yang Sudah Dibuat

### 1. Splash Screen
- Logo aplikasi teknisi
- Nama aplikasi: "MySimtek - Teknisi"
- Versi aplikasi

### 2. Login Screen
- Input username (bukan email, sesuai API teknisi)
- Input password dengan toggle visibility
- Validasi role (hanya teknisi yang bisa login)
- Error handling dan loading state
- UI konsisten dengan MySimtek Pelanggan

### 3. Dashboard (TeknisiShell)
- Bottom navigation dengan 2 tab:
  - **Beranda**: Halaman utama
  - **Akun**: Profil dan pengaturan

### 4. Beranda Screen
- Welcome card dengan nama teknisi
- Statistik cards (TRB Ticket, PSB Ticket, Jadwal, Notifikasi)
- Menu grid dengan 6 menu utama:
  - TRB Ticket
  - PSB Ticket
  - Jadwal Instalasi
  - Data ODP
  - Peta Area
  - Notifikasi

### 5. Akun Screen
- Profile card dengan avatar dan username
- Informasi akun (nama, username, email, telepon)
- Menu pengaturan:
  - Ubah Password
  - Tentang Aplikasi
  - Keluar (dengan konfirmasi dialog)

## API Endpoints Tersedia

Sudah disiapkan di `api_constants.dart`:

### Auth
- `POST /login` - Login teknisi
- `POST /logout` - Logout
- `GET /me` - Get user profile
- `POST /verify-password` - Verifikasi password
- `POST /change-password` - Ubah password

### TRB Tickets
- `GET /teknisi/tickets` - List TRB tickets
- `GET /teknisi/tickets/{id}` - Detail ticket
- `POST /teknisi/tickets/{id}/claim` - Claim ticket
- `POST /teknisi/tickets/{id}/start` - Mulai pekerjaan
- `POST /teknisi/tickets/{id}/field-report` - Submit laporan
- `POST /teknisi/tickets/{id}/messages` - Kirim pesan

### PSB Tickets
- `GET /teknisi/psb-tickets` - List PSB tickets
- `GET /teknisi/psb-tickets/{id}` - Detail ticket
- `POST /teknisi/psb-tickets/{id}/claim` - Claim ticket
- `POST /teknisi/psb-tickets/{id}/start` - Mulai instalasi
- `POST /teknisi/psb-tickets/{id}/field-report` - Submit laporan
- `POST /teknisi/psb-tickets/{id}/messages` - Kirim pesan

### Lainnya
- `GET /teknisi/odp` - List ODP
- `GET /teknisi/jadwal` - Jadwal instalasi
- `GET /teknisi/map-data` - Data peta
- `GET /teknisi/notifications` - Notifikasi

## Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  provider: ^6.1.1          # State management
  http: ^1.1.0              # HTTP client
  shared_preferences: ^2.2.2 # Local storage
  google_fonts: ^6.1.0      # Font Poppins
```

## Cara Menjalankan

```bash
# Install dependencies
flutter pub get

# Run app
flutter run
```

## Next Steps (TODO)

Fitur yang bisa ditambahkan selanjutnya:

1. **TRB Ticket Management**
   - List TRB tickets
   - Detail ticket dengan messages
   - Claim & Start ticket
   - Submit field report dengan foto
   - Chat/messaging

2. **PSB Ticket Management**
   - List PSB tickets
   - Detail ticket dengan info pelanggan
   - Claim & Start instalasi
   - Submit field report dengan detail teknis (ONT serial, cable length, signal strength, foto)
   - Chat/messaging

3. **Jadwal Instalasi**
   - Calendar view
   - List jadwal hari ini/minggu ini
   - Detail jadwal dengan lokasi

4. **ODP Management**
   - List ODP
   - Detail ODP dengan kapasitas
   - Filter & search ODP

5. **Map View**
   - Peta lokasi ODP
   - Peta lokasi customer
   - Navigasi ke lokasi

6. **Notifications**
   - List notifikasi
   - Mark as read
   - Badge counter
   - FCM integration

7. **Change Password**
   - Ubah password dengan verifikasi password lama

8. **About App**
   - Info versi
   - Developer info

## Referensi

- API Documentation: `simtek-billing/references/teknisi_api_mobile.md`
- Customer App: `mysimtek/lib/features/customer/`
- Backend Routes: `simtek-billing/routes/api.php`
