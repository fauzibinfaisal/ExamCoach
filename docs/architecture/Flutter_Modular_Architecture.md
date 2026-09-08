# ExamCoach — Flutter Modular Architecture

## Structure

```text
lib/
├── app/
├── core/
├── shared/
├── bootstrap/
├── services/
├── learning_engine/
├── ai/
├── analytics/
└── features/
    ├── auth/
    ├── onboarding/
    ├── home/
    ├── practice/
    ├── exam/
    ├── result/
    ├── insight/
    ├── ai_coach/
    ├── leaderboard/
    ├── subscription/
    └── profile/
```

## Feature Structure

```text
feature/
├── data/
├── domain/
├── application/
└── presentation/
```

## Responsibilities
Data: repositories, DTOs, remote/local sources.
Domain: entities and business contracts.
Application: Bloc/Cubit and workflow orchestration.
Presentation: pages, widgets, UI state.

## Rules
Core learning logic should be pure Dart where possible and independent of widgets.
Bloc manages workflow/state, not complex scoring algorithms.

## Offline
Use local repositories, sync queue, connectivity observer, and conflict handler.

The implemented `features/auth` module separates Firebase data access,
account-binding/recovery domain contracts, auth Cubit orchestration, and account
presentation. `services/firebase` owns optional runtime initialization, while
`services/sync` keeps the provider-neutral gateway and Firebase adapter behind
the same worker contract. Missing Firebase configuration must not cross into or
disable the learning feature.

## Engineering Priority
Build and test:
Question → Answer → Score → Weakness → Recommendation → Drill → Updated Insight
before major architecture refinement.
