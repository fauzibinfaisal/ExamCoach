# ExamCoach — Enterprise Taxonomy Design

## Hierarchy

```text
Exam
└── Test
    └── Domain
        └── Topic
            └── Subtopic
                └── Skill
                    └── MicroSkill
```

## Example

```text
CPNS
└── TIU
    └── Numerik
        └── Aritmatika
            └── Persentase
                └── Konversi
                    └── Persen ke Pecahan
```

## Question Metadata
- exam/test/domain/topic/subtopic/skill/microSkill IDs
- difficulty dimensions
- cognitive type
- estimated time
- trap type
- source/provenance
- explanation
- validation status
- content version

## Difficulty
Represent conceptual difficulty, calculation complexity, time pressure, and distractor/trap complexity separately where useful.

## Governance
Taxonomy changes must be versioned, reviewed, auditable, and referenced by stable IDs.

## AI
AI may suggest classifications, but controlled human workflow validates final taxonomy mapping.
