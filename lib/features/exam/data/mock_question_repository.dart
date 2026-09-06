import 'package:exam_coach/features/exam/domain/models/question.dart';
import 'package:exam_coach/features/exam/domain/models/taxonomy_path.dart';
import 'package:exam_coach/features/exam/domain/repositories/question_repository.dart';

class MockQuestionRepository implements QuestionRepository {
  MockQuestionRepository() : _questions = List.unmodifiable(_buildQuestions());

  final List<Question> _questions;

  static const _ratioTaxonomy = TaxonomyPath(
    examId: 'exam_cpns',
    testId: 'test_tiu',
    domainId: 'domain_numerik',
    topicId: 'topic_ratio',
    subtopicId: 'subtopic_perbandingan',
    skillId: 'skill_operasi_ratio',
    microSkillId: 'micro_ratio_context',
    topicLabel: 'Perbandingan',
  );

  static const _sequenceTaxonomy = TaxonomyPath(
    examId: 'exam_cpns',
    testId: 'test_tiu',
    domainId: 'domain_numerik',
    topicId: 'topic_number_sequence',
    subtopicId: 'subtopic_pola_bilangan',
    skillId: 'skill_identifikasi_pola',
    microSkillId: 'micro_next_number',
    topicLabel: 'Deret Angka',
  );

  static const _analogyTaxonomy = TaxonomyPath(
    examId: 'exam_cpns',
    testId: 'test_tiu',
    domainId: 'domain_verbal',
    topicId: 'topic_word_analogy',
    subtopicId: 'subtopic_relasi_kata',
    skillId: 'skill_identifikasi_relasi',
    microSkillId: 'micro_profession_place',
    topicLabel: 'Analogi Kata',
  );

  @override
  List<Question> get allQuestions => _questions;

  @override
  List<Question> get initialTryoutQuestions => List.unmodifiable([
    _questions[0],
    _questions[1],
    _questions[4],
    _questions[5],
    _questions[8],
    _questions[9],
  ]);

  static List<Question> _buildQuestions() => [
    _question(
      id: 'q_ratio_01',
      prompt:
          'Perbandingan siswa laki-laki dan perempuan adalah 3 : 5. Jika total siswa 40 orang, berapa jumlah masing-masing?',
      options: const ['12 dan 28', '15 dan 25', '18 dan 22', '20 dan 20'],
      correctIndex: 1,
      taxonomy: _ratioTaxonomy,
      difficulty: QuestionDifficulty.easy,
      explanation:
          'Total bagian 3 + 5 = 8. Setiap bagian bernilai 40 ÷ 8 = 5, sehingga jumlahnya 15 dan 25.',
    ),
    _question(
      id: 'q_ratio_02',
      prompt:
          'Sebuah barang seharga Rp200.000 mendapat diskon 15%. Berapa harga setelah diskon?',
      options: const ['Rp165.000', 'Rp170.000', 'Rp175.000', 'Rp185.000'],
      correctIndex: 1,
      taxonomy: _ratioTaxonomy,
      difficulty: QuestionDifficulty.medium,
      explanation:
          'Diskon 15% × Rp200.000 = Rp30.000. Harga akhir adalah Rp170.000.',
    ),
    _question(
      id: 'q_ratio_03',
      prompt:
          'Larutan A dan B dicampur dengan perbandingan 2 : 3. Jika campuran berjumlah 25 liter, berapa liter larutan A?',
      options: const ['10 liter', '12 liter', '15 liter', '20 liter'],
      correctIndex: 0,
      taxonomy: _ratioTaxonomy,
      difficulty: QuestionDifficulty.medium,
      explanation:
          'Bagian A adalah 2 dari total 5 bagian, sehingga volumenya 2/5 × 25 = 10 liter.',
    ),
    _question(
      id: 'q_ratio_04',
      prompt:
          'Pada peta berskala 1 : 50.000, jarak dua kota adalah 6 cm. Berapa jarak sebenarnya?',
      options: const ['300 meter', '1,5 km', '3 km', '30 km'],
      correctIndex: 2,
      taxonomy: _ratioTaxonomy,
      difficulty: QuestionDifficulty.hard,
      explanation: '6 × 50.000 cm = 300.000 cm, setara dengan 3 km.',
    ),
    _question(
      id: 'q_sequence_01',
      prompt: 'Angka berikutnya pada deret 2, 5, 10, 17, 26, ... adalah?',
      options: const ['33', '35', '37', '39'],
      correctIndex: 2,
      taxonomy: _sequenceTaxonomy,
      difficulty: QuestionDifficulty.medium,
      explanation:
          'Selisihnya berurutan 3, 5, 7, dan 9. Selisih berikutnya 11, sehingga jawabannya 37.',
    ),
    _question(
      id: 'q_sequence_02',
      prompt: 'Angka berikutnya pada deret 3, 6, 12, 24, ... adalah?',
      options: const ['30', '36', '42', '48'],
      correctIndex: 3,
      taxonomy: _sequenceTaxonomy,
      difficulty: QuestionDifficulty.easy,
      explanation: 'Setiap bilangan dikalikan dua. Jadi 24 × 2 = 48.',
    ),
    _question(
      id: 'q_sequence_03',
      prompt: 'Angka berikutnya pada deret 81, 27, 9, 3, ... adalah?',
      options: const ['0', '1', '2', '6'],
      correctIndex: 1,
      taxonomy: _sequenceTaxonomy,
      difficulty: QuestionDifficulty.easy,
      explanation: 'Setiap bilangan dibagi tiga. Jadi 3 ÷ 3 = 1.',
    ),
    _question(
      id: 'q_sequence_04',
      prompt: 'Angka berikutnya pada deret 4, 7, 13, 22, 34, ... adalah?',
      options: const ['46', '47', '48', '49'],
      correctIndex: 3,
      taxonomy: _sequenceTaxonomy,
      difficulty: QuestionDifficulty.hard,
      explanation:
          'Selisih bertambah tiga: 3, 6, 9, 12, lalu 15. Jadi 34 + 15 = 49.',
    ),
    _question(
      id: 'q_analogy_01',
      prompt: 'Dokter : Rumah Sakit = Guru : ...',
      options: const ['Perpustakaan', 'Sekolah', 'Kantor', 'Laboratorium'],
      correctIndex: 1,
      taxonomy: _analogyTaxonomy,
      difficulty: QuestionDifficulty.easy,
      explanation:
          'Hubungannya adalah profesi dengan tempat utama bekerja: guru bekerja di sekolah.',
    ),
    _question(
      id: 'q_analogy_02',
      prompt: 'Benih : Tumbuhan = Telur : ...',
      options: const ['Sarang', 'Cangkang', 'Burung', 'Bulu'],
      correctIndex: 2,
      taxonomy: _analogyTaxonomy,
      difficulty: QuestionDifficulty.medium,
      explanation:
          'Hubungannya adalah bentuk awal dengan hasil pertumbuhannya: telur berkembang menjadi burung.',
    ),
    _question(
      id: 'q_analogy_03',
      prompt: 'Termometer : Suhu = Timbangan : ...',
      options: const ['Panjang', 'Berat', 'Waktu', 'Kecepatan'],
      correctIndex: 1,
      taxonomy: _analogyTaxonomy,
      difficulty: QuestionDifficulty.easy,
      explanation:
          'Keduanya adalah alat ukur: termometer mengukur suhu dan timbangan mengukur berat.',
    ),
    _question(
      id: 'q_analogy_04',
      prompt: 'Kapten : Kapal = Dirigen : ...',
      options: const ['Panggung', 'Lagu', 'Orkestra', 'Penonton'],
      correctIndex: 2,
      taxonomy: _analogyTaxonomy,
      difficulty: QuestionDifficulty.hard,
      explanation:
          'Hubungannya adalah pemimpin dengan kelompok yang dipimpin: dirigen memimpin orkestra.',
    ),
  ];

  static Question _question({
    required String id,
    required String prompt,
    required List<String> options,
    required int correctIndex,
    required TaxonomyPath taxonomy,
    required QuestionDifficulty difficulty,
    required String explanation,
  }) {
    const optionIds = ['a', 'b', 'c', 'd'];
    return Question(
      id: id,
      prompt: prompt,
      options: [
        for (var index = 0; index < options.length; index++)
          QuestionOption(id: optionIds[index], text: options[index]),
      ],
      correctOptionId: optionIds[correctIndex],
      taxonomy: taxonomy,
      difficulty: difficulty,
      cognitiveType: 'reasoning',
      estimatedTime: const Duration(seconds: 60),
      trapType: 'plausible_distractor',
      provenance: 'development_prototype_original',
      author: 'examcoach_development_team',
      reviewer: null,
      explanation: explanation,
      validationStatus: QuestionValidationStatus.draft,
      version: 1,
    );
  }
}
