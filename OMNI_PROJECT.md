# OMNI_AI — Living Project Skeleton

## 1. Project Identity

**Project:** OMNI_AI

OMNI_AI — единый персональный AI-хаб, объединяющий AI, персонализированный контент, медиа, новости, события, уведомления, финансы, семью, здоровье и другие пользовательские сценарии в одной экосистеме.

Главный принцип:

> OMNI_AI — это единая система, а не набор независимых приложений.

Пользователь взаимодействует прежде всего с OMNI_AI и его AI-персоной, а отдельные источники и сервисы работают как внутренние модули.

---

## 2. Current Development Baseline

**Repository:** `vanes961/omni_ai`

**Current branch:** `main`

**Stable baseline:** `6f290ce`

**Baseline commit:** `feat: update media network and telegram integration`

Android является главным целевым направлением разработки.

Проект не переписывается с нуля. Новая функциональность должна расширять существующий фундамент.

---

## 3. Current Repository Structure

```text
lib/
├── main.dart
├── core/
│   └── network/
│       ├── mirror_resolver.dart
│       ├── network_client_io.dart
│       ├── network_client_stub.dart
│       ├── network_client_web.dart
│       ├── network_service.dart
│       ├── proxy_config.dart
│       └── widgets/
│           └── network_image_with_fallback.dart
│
└── features/
    ├── dashboard/
    │   └── presentation/
    │       └── dashboard_page.dart
    │
    ├── media/
    │   ├── data/
    │   │   └── media_item.dart
    │   ├── presentation/
    │   │   ├── media_page.dart
    │   │   └── player_page.dart
    │   └── services/
    │       ├── media_headers.dart
    │       └── media_search_service.dart
    │
    ├── onboarding/
    │   ├── data/
    │   │   └── user_preferences.dart
    │   └── presentation/
    │       └── onboarding_page.dart
    │
    ├── run_history/
    │   ├── data/
    │   │   ├── in_memory_run_history_repository.dart
    │   │   └── shared_preferences_run_history_repository.dart
    │   ├── models/
    │   │   └── process_run_record.dart
    │   ├── presentation/
    │   │   └── run_history_page.dart
    │   ├── repositories/
    │   │   └── run_history_repository.dart
    │   └── services/
    │       └── run_history_recorder.dart
    │
    ├── settings/
    │   └── presentation/
    │       └── pages/
    │           └── network_settings_page.dart
    │
    ├── system_core/
    │   ├── models/
    │   │   └── system_core_process_state.dart
    │   ├── presentation/
    │   │   ├── system_core_page.dart
    │   │   ├── system_core_palette.dart
    │   │   └── system_core_widgets.dart
    │   └── services/
    │       └── system_core_process_service.dart
    │
    └── telegram/
        ├── data/
        │   └── telegram_post.dart
        ├── presentation/
        │   └── widgets/
        │       └── telegram_post_card.dart
        └── services/
            └── telegram_parser_service.dart
4. Current Dependencies
flutter
cupertino_icons
shared_preferences
video_player
url_launcher
http
cached_network_image

Development dependencies:

flutter_test
flutter_lints

Do not introduce a dependency merely for convenience. New dependencies must have a clear architectural or functional reason.

5. Core Product Architecture

Target architecture:

                         OMNI_AI
                            │
                    ┌───────▼───────┐
                    │   AI AGENT    │
                    └───────┬───────┘
                            │
                    ┌───────▼───────┐
                    │   AI ENGINE   │
                    └───────┬───────┘
                            │
                    ┌───────▼───────┐
                    │ EVENT ENGINE  │
                    └───────┬───────┘
                            │
        ┌──────────┬────────┼────────┬───────────┐
        ↓          ↓        ↓        ↓           ↓
      NEWS       MEDIA     GAMES   FAMILY      HEALTH
        │          │        │        │           │
 Telegram/RSS    Movies   Android  School     Huawei
 Web/API         Anime    Games    Location   Xiaomi
                 Series           Grades
                 Trailers         Homework
        │          │        │        │           │
        └──────────┴────────┼────────┴───────────┘
                            ↓
                     USER INTERESTS
                            ↓
                         MEMORY
                            ↓
                      NOTIFICATION
                            ↓
                     GOOGLE CALENDAR
6. Core Systems

Planned core systems:

AI Core
AI Agent
Personal Preference Engine
Memory
Event Engine
Notification Engine
Follow System
Network
Storage
Error Guard / OMNI Guard
System Core
Run History
7. Personal Preference Engine

OMNI_AI should learn the user's preferences continuously.

Signals include:

onboarding answers;
opened content;
saved content;
skipped content;
read content;
watched content;
listened content;
followed items;
genres;
themes;
creators;
composers;
categories;
repeated behavior.

The system should gradually build a richer user preference profile instead of relying only on explicit questionnaire answers.

8. Event Engine

The Event Engine is responsible for converting external information into normalized OMNI events.

Sources
   ↓
Event Engine
   ↓
Normalize
   ↓
Deduplicate
   ↓
Classify
   ↓
Rank
   ↓
AI analysis
   ↓
User interest / priority
   ↓
Feed + Notifications + Calendar

The Event Engine should support events such as:

new releases;
new episodes;
new chapters;
trailers;
updates;
followed-item changes;
important news;
relevant external events.
9. Follow System

Generic followed-item model:

FollowedItem

Types:
- Movie
- Series
- Anime
- Manga
- Game
- Trailer
- Music
- Other supported media

Following an item allows OMNI_AI to monitor relevant events and surface them through the personalized feed and notifications.

10. AI Agent

The same OMNI AI persona should be present across the application.

It should appear in:

onboarding;
main OMNI experience;
Live AI;
finance;
recommendations;
recipes;
future assistant scenarios.

The persona should feel like one continuous assistant rather than separate assistants for every module.

11. Onboarding

First launch flow:

Splash / cinematic intro
        ↓
AI persona
        ↓
Natural conversation
        ↓
Preference discovery
        ↓
Initial profile
        ↓
Personalized OMNI home

Onboarding should not be limited to a rigid questionnaire.

The AI should determine when enough information has been collected.

Final transition concept:

«Готово. Теперь я знаю достаточно, чтобы собрать твой OMNI.»

The preference profile then continues learning from behavior.

12. Home / Dashboard

The main home should evolve into a personalized OMNI feed.

It should not become a grid of unrelated services.

The feed should combine relevant information from:

News
Media
Games
Music
Followed items
Events
Recommendations
Notifications
Other enabled OMNI modules

Priority should be determined by the Event Engine and Personal Preference Engine.

13. News

Telegram is a source of information, not the destination.

OMNI_AI should aggregate and normalize information from:

Telegram
RSS
Web
APIs
Other supported sources

The user should consume relevant information inside OMNI whenever possible.

14. Media

Media includes:

Movies
Series
Anime
Trailers
Favorites
Follow/watch lists
Recommendations
Player
Release events
Episode events
Dubbing changes

Current Media already contains:

metadata search;
poster loading;
ratings;
genres;
descriptions;
image fallback;
local catalog fallback;
filters;
player architecture;
episode source switching;
preferred dubbing;
network retry/fallback behavior.

Playback sources must remain legitimate and supported. Do not invent or add unauthorized stream extraction.

15. Manga

Future Manga module:

catalog;
search;
favorites;
reading list;
reading history;
embedded reader;
automatic reading-position saving;
new chapter detection;
notifications;
AI recommendations.

Reader modes:

vertical;
single page;
two-page;
width controls;
dark mode;
prefetch.

Foldable devices should support expanded reading layouts.

16. Games

Future Games module:

Android games;
new releases;
updates;
trailers;
favorites;
follows;
AI recommendations;
event notifications.
17. Music

Future Music module.

Desired direction includes Yandex Music integration where technically and legally supported.

OMNI should learn:

artists;
genres;
tracks;
albums;
composers;
listening behavior.

A persistent mini-player is planned.

Before implementation, official API capabilities and current integration limitations must be verified.

18. My Finances

Future module name:

Мои финансы

The module contains an E-консультант using the same OMNI AI persona.

User can enter financial information by:

text;
voice.

Examples:

«Запиши, что я потратил 46 евро на ...»

«Я получаю 3200 евро в месяц.»

The system should support:

income;
expenses;
categories;
recurring payments;
subscriptions;
budgets;
financial goals;
spending analysis;
forecasts;
unusual-spending detection;
category growth;
budget-limit warnings;
saving goals.

Example goal:

Цель: €3000
Текущий прогресс: ...
Цель в месяц: ...
Оценка срока: ...

Conceptual domain model:

Finance
├── Income
├── Expense
├── Budget
├── RecurringPayment
├── FinancialGoal
├── FinanceAnalysis
└── FinanceMemory

Financial raw data should remain a separate protected domain and should not automatically become general-purpose memory.

The AI is an advisor.

It must not independently transfer money, purchase financial products, or perform financial actions without explicit user authorization.

Initial implementation should focus on manual/voice entry, local financial models and AI analytics.

19. My Recipes / AI Food

Future module:

Мои рецепты / AI Food

Core flow:

Photo of dish
      ↓
AI identifies dish
      ↓
Ingredients
      ↓
Recipe generation
      ↓
Save recipe
      ↓
Recipe card

Saved recipe card contains:

photo;
dish name;
ingredients;
recipe;
preparation steps.

Future enrichment:

variants;
ingredient substitutions;
portion scaling;
cooking advice;
nutrition-related improvements;
favorites.

Example AI requests:

«Сделай менее калорийным.»

«Чем заменить сливки?»

«Рассчитай на 5 человек.»

«Добавь в мои любимые.»

Potential future integration:

AI Food
   ├── Health
   ├── Finance
   └── future ingredient/shopping systems

This module is a future concept and should not be implemented until its development stage is reached.

20. Family / School

Family is intended primarily as a family/education system.

Potential functions:

child location;
school information;
grades;
homework;
AI analysis;
advice.

Official APIs and platform capabilities must be verified before implementation.

21. Health

Future Health module.

Potential integrations:

Huawei Watch GT 2 / supported Huawei Health data;
Xiaomi smart scales / supported Xiaomi data.

OMNI should analyze trends and provide general wellness information.

It must not present itself as a medical diagnostic system.

Third-party API availability must be verified before implementation.

22. Google Calendar

Google Calendar integration is planned.

Potential uses:

release events;
important followed-item events;
reminders;
user-selected notifications.

The user must control what gets synchronized.

23. Foldables / Adaptive UI

HONOR Magic V2 is a real target test device.

OMNI_AI must support:

normal smartphones;
foldables;
portrait;
landscape;
folded state;
expanded state.

Foldable UI must not simply stretch the phone layout.

Where appropriate, expanded mode should use two-pane layouts.

Examples:

Manga reader: expanded reading layout;
Live AI: conversation + contextual information;
Media: catalog + details/player context.

Adaptive architecture should be considered from the beginning.

24. Visual Direction

Primary visual identity:

dark;
cinematic;
sci-fi;
cyberpunk;
fantasy influence;
neon accents;
terminal-inspired details;
smooth transitions;
high-refresh-rate friendly animation;
reactive UI;
depth and layered panels.

Future visual direction may include:

particles;
reactive effects;
3D OMNI core;
mode-dependent visual states;
cinematic splash animations.

3D should be introduced after the core architecture and interaction model are stable.

The application should remain performant on real Android hardware.

25. Splash / Cinematic Introduction

The splash should eventually be a short cinematic experience rather than a simple loading spinner.

Desired characteristics:

short scenes;
motion;
atmospheric effects;
possible randomized variants;
transition into the OMNI interface.

Exact copyrighted characters/assets should only be used where legally permitted or where appropriate assets are supplied.

26. OMNI Guard

The existing Guard concept should evolve into a reliability/security layer.

Potential responsibilities:

error handling;
network protection;
AI action control;
module health;
failure recovery;
logging;
safe cancellation;
future voice/action authorization.

OMNI Guard is a system layer, not merely a decorative AI indicator.

27. System Core

Existing System Core is part of the foundation.

It should remain independent from individual UI modules and provide a reliable way to execute system operations through interfaces.

Existing capabilities include process state management, cancellation and run history integration.

28. Run History

Existing Run History provides persistence for system operations.

The current implementation uses SharedPreferences and repository abstractions.

It should remain independent of UI and support future system/AI operations.

29. Target Architecture Direction

Future target structure:

lib/
├── app/
│   ├── app.dart
│   ├── router.dart
│   └── theme.dart
│
├── core/
│   ├── ai_engine/
│   ├── memory/
│   ├── preferences/
│   ├── events/
│   ├── notifications/
│   ├── follow/
│   ├── error_guard/
│   ├── network/
│   ├── storage/
│   └── utils/
│
├── features/
│   ├── onboarding/
│   ├── home/
│   ├── ai_agent/
│   ├── news/
│   ├── media/
│   ├── games/
│   ├── manga/
│   ├── music/
│   ├── calendar/
│   ├── family/
│   ├── school/
│   ├── health/
│   ├── finance/
│   └── ai_food/
│
├── system/
│   ├── system_core/
│   └── run_history/
│
└── main.dart

This is the target direction, not a command to create every folder immediately.

30. AI Engine Architecture Rule

The AI Engine should expose neutral request/response/error models.

Provider-specific SDKs must not leak into UI.

Target principles:

async execution;
cancellation;
timeout;
provider adapter isolation;
testable fake engine;
no direct provider dependency in presentation code.
31. Development Order

Initial recommended sequence:

Existing System Core
AI Engine
Personal Preference Engine
Event Engine
Follow System
Main personalized Home
News
Movies / Series / Anime expansion
Games
Manga
Music
Live AI
Google Calendar
Family / School
Health
Finance
AI Food / Recipes
Final visual/performance polish

This order can change when architecture or product priorities require it.

32. Development Rules
Do not rewrite the project from scratch.
Preserve working functionality.
Work in small, testable increments.
Do not introduce unnecessary dependencies.
Keep provider-specific code isolated.
Keep sensitive domains separated.
Do not put secrets into SharedPreferences.
UI must not directly own core business logic.
New modules should communicate through interfaces/services.
Every significant architectural decision must be documented.
Every completed milestone should update this document.
Before large changes, establish a Git checkpoint.
Run tests after meaningful changes.
Android is the primary target.
Foldable support must be considered from the architecture stage.
Visual quality is part of the product, but visual effects must not compromise reliability or performance.
33. Current Development State
Completed / existing
Flutter application foundation
System Core
Run History
Network layer
Network image fallback
Dashboard
Onboarding foundation
Telegram parsing/feed foundation
Media catalog foundation
Media metadata/search integration
Player foundation
Network settings
Shared Preferences persistence
Current stable baseline

6f290ce

Working tree note

At the time this document was created, generated Flutter platform files for Linux/macOS/Windows had local modifications. They are not part of the Android feature baseline and should not be committed without a deliberate reason.

34. Immediate Next Phase

The next architectural phase is to establish the AI Engine foundation.

Before implementing a large AI feature, define:

AI Request
    ↓
AI Engine
    ↓
Provider Adapter
    ↓
AI Response

The engine must support future use by:

onboarding;
recommendations;
Event Engine;
finance;
AI Food;
Live AI;
other OMNI modules.

The first implementation should be minimal, testable and provider-independent.

35. Project Memory Rule

This document is the living source of truth for the OMNI_AI project.

Chat conversations are not sufficient as the only project memory.

Whenever an important idea, architecture decision, module, constraint or milestone is agreed upon, update this document.

When a development session ends after a meaningful milestone:

update this document;
run tests;
create a Git checkpoint;
push the stable checkpoint when appropriate.
36. Future Ideas

Ideas that are approved conceptually but not yet implemented should be recorded here rather than lost in conversation.

Current future ideas include:

Personal Preference Engine
Event Engine
Follow System
personalized OMNI Home
AI Agent
Live AI
Games
Manga
Music
Google Calendar
Family / School
Health
Мои финансы
Мои рецепты / AI Food
advanced OMNI Guard
cinematic splash
reactive/3D OMNI visual core
37. Status

Project status: Active development

Current baseline: 6f290ce

Next major architectural target: AI Engine foundation

Document purpose: Preserve product vision, architecture, decisions and development state across AI sessions and coding environments.
