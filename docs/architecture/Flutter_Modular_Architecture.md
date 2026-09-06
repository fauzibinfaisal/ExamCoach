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

## Engineering Priority
Build and test:
Question → Answer → Score → Weakness → Recommendation → Drill → Updated Insight
before major architecture refinement.
