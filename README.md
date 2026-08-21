# Intact

Нативное, элегантное и быстрое приложение для меню-бара macOS: диктовка по горячей клавише с локальным распознаванием через whisper.cpp. 100% приватность: звук и текст никогда не покидают ваше устройство.

## Особенности

- **Мгновенная вставка**: распознавание черновиков прямо во время речи с нулевой задержкой при отпускании клавиши.
- **Интерфейс в стиле Wispr Flow**: теплые органические оттенки, Serif-заголовки, плавные переключатели и карточки.
- **Управление звуком и плеерами**: автоматическое заглушение системного звука и пауза Apple Music / Spotify во время диктовки.
- **Проверка и обновление моделей**: автоматическая проверка актуальности моделей Whisper на Hugging Face в один клик.
- **Гибкая активация**: удержание любой клавиши (например, `⌥ Option`, `Fn`, `⌘ Command`) или глобальное сочетание клавиш.
- **Словарь терминов и перевод**: поддержка `initialPrompt` для точного распознавания специализированного сленга и возможность автоперевода на английский.

## Требования

- macOS 14+ (Sonoma, Sequoia), Apple Silicon
- `brew install whisper-cpp` — локальный движок распознавания
- Модели ggml в `~/Models/whisper/` (скачиваются и обновляются прямо из вкладки «Модель»)

## Сборка и установка

```bash
./build.sh
```

Скрипт собирает release-бинарник, упаковывает в `Intact.app`, подписывает локальным сертификатом (или ad-hoc) и устанавливает в `/Applications/Intact.app`.

## Структура проекта

| Файл | Назначение |
|---|---|
| `IntactApp.swift` | Точка входа, строка меню (`MenuBarExtra`), `AppDelegate`, активация |
| `DictationController.swift` | Оркестрация жизненного цикла: запись → черновики → вставка |
| `WhisperServer.swift` | Фоновый сервис `whisper-server` с загруженной моделью и HTTP API |
| `MediaController.swift` | Заглушение системного звука и авто-пауза музыки во время речи |
| `ModelManager.swift` | Каталог моделей Hugging Face, скачивание, проверка ETag и обновление |
| `ModifierKeyMonitor.swift` | Отслеживание удержания модификаторов (`⌥`, `⌘`, `⌃`, `⇧`) через CGEventTap |
| `AudioRecorder.swift` | AVAudioEngine, 16 кГц моно, расчет RMS уровня громкости и срез WAV |
| `Transcriber.swift` | Резервный режим через `whisper-cli` |
| `HotKeyManager.swift` | Глобальные сочетания клавиш через Carbon Events API |
| `TextInserter.swift` | Вставка через Accessibility API / ⌘V буфер обмена |
| `Settings.swift` | Постоянные настройки пользователя в UserDefaults |
| `History.swift` | Локальная история последних распознаваний |
| `LiveTyper.swift` | Потоковая печать текста в активное поле во время речи |
| `Views/Theme.swift` | Дизайн-система: цвета Palette, стили свитчей WisprToggleStyle, типографика |
| `Views/SettingsView.swift` | Панель настроек с разделами General, System, Model, Language, Mic, History, About |
| `Views/RecordingIndicator.swift` | Плавающий индикатор записи с живой звуковой волной |

## Разрешения macOS

1. **Микрофон** (`NSMicrophoneUsageDescription`) — для захвата голоса.
2. **Мониторинг ввода** (Input Monitoring) — для считывания зажатия клавиши-модификатора (`⌥ Option`).
3. **Универсальный доступ** (Accessibility) — для эмуляции вставки текста в фокусные поля приложений.

При сбросе разрешений:
```bash
tccutil reset Accessibility com.artsu.intact
tccutil reset ListenEvent com.artsu.intact
```
