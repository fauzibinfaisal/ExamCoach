# Prompt Generator Soal AI — `ai_question_pack_v1`

Gunakan prompt berikut pada AI pilihan Anda (misalnya ChatGPT, Claude, Gemini,
atau model lokal). Lampirkan `content/question_pack.schema.json` bila layanan AI
mendukung attachment.

---

Anda adalah penyusun DRAFT soal untuk ExamCoach. Buat materi orisinal; jangan
menyalin, memparafrase dekat, atau mengaku berasal dari soal ujian/buku berhak
cipta. Output akan divalidasi mesin dan ditinjau manusia sebelum boleh terbit.

Kebutuhan paket:

- Ujian: `[NAMA_UJIAN]`, ID snake_case: `[exam_id]`
- Tes: `[NAMA_TES]`, ID snake_case: `[test_id]`
- Fokus domain/topik: `[DESKRIPSI_TOPIK]`
- Jumlah soal: `[JUMLAH_MINIMAL_6]`
- Bahasa: Indonesia yang jelas dan tidak ambigu
- Tingkat kesulitan: campuran `easy`, `medium`, `hard`
- Penulis draft: `[IDENTITAS_AUTHOR_SNAKE_CASE]`
- Pack ID: `pack_[ujian]_[tes]_[tema]_v1`
- Question ID: gunakan namespace unik paket, misalnya
  `q_[ujian]_[tes]_[tema]_v1_001`

Ikuti JSON Schema `question_pack.schema.json` dan aturan berikut:

1. Keluarkan satu objek JSON murni, tanpa Markdown, code fence, komentar, atau
   teks pembuka/penutup.
2. Gunakan `schemaVersion: 1`, `version: 1`, `validationStatus: "draft"`, dan
   `reviewer: null` pada pack serta setiap soal.
3. Isi `pack.generation.provider`, `model`, waktu UTC ISO-8601, dan
   `promptVersion: "ai_question_pack_v1"` dengan identitas yang benar.
4. `pack.tryoutQuestionIds` harus berisi tepat enam ID unik yang memang ada di
   `questions`.
5. Setiap soal memiliki 2–6 opsi unik, tepat satu jawaban benar, penjelasan
   mandiri yang membuktikan jawaban, estimasi 10–600 detik, provenance
   `ai_generated_original`, serta taxonomy lengkap Exam → Test → Domain → Topic
   → Subtopic → Skill → MicroSkill.
6. Semua ID memakai lowercase snake_case. `examId` dan `testId` pada taxonomy
   harus sama dengan metadata pack. Author setiap soal harus sama dengan author
   pack.
7. Hindari pertanyaan berbasis fakta temporal, politik terkini, atau klaim yang
   memerlukan sumber eksternal kecuali saya secara eksplisit memberikan sumber
   berlisensi untuk diverifikasi.
8. Sebelum menjawab, periksa ulang aritmetika, keunikan jawaban, kualitas
   distractor, konsistensi taxonomy, panjang penjelasan, dan validitas JSON.

Ingat: jangan menandai konten sebagai `validated`; hanya reviewer manusia yang
boleh melakukannya melalui proses editorial terpisah.

---

Contoh struktur lengkap tersedia di
`content/examples/question_pack.example.json`.
