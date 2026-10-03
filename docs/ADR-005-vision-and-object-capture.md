# ADR-005: Capture from text, book pages and objects

## Status
Accepted (revised 2026-10-04: APIs verified, technology chosen; page recognition details corrected
when it was built)

## Date
2026-10-03

## Context
The owner asked for three capture sources and left the technology choice to the implementer:
1. text the learner is reading on a device;
2. a page of a physical book, photographed;
3. an object around them, photographed, to learn its name.

Capture must work on iPhone, iPad and Mac, offline where possible, without sending images to a
server by default.

The first version of this ADR referenced `VNClassificationRequest`, which does not exist. The
classifier is `ClassifyImageRequest` (Swift API) / `VNClassifyImageRequest`.

## Decision
- **Text:**
  - In-app paste/typing.
  - A Share extension for iOS/iPadOS and macOS that accepts plain text.
  - A macOS Services menu item. The handler receives the selected string and opens quick capture.
  - Text is tokenized with `NLTokenizer`. The learner taps a word or selects a span. The context is
    the sentence containing the selection (`NLTokenizer(unit: .sentence)`).
- **Book page:**
  - The learner takes a photo (camera on iPhone/iPad) or picks an image (PhotosPicker, Files,
    drag-and-drop on Mac).
  - Run Vision **`RecognizeDocumentsRequest`** (iOS/macOS 26). It returns paragraphs whose
    `transcript` joins wrapped lines, each with `words` (per-word observations and normalized boxes).
  - The app draws tappable word boxes over the image. A tap extracts the sentence that contains the
    word from the paragraph transcript.
  - Words come with their punctuation (`Bank,`), which is trimmed. Each word is matched to its place
    in the transcript in reading order, so a word that appears twice gets the sentence it is in.
  - Recognition is guided by the learner's languages. The request supports all 19 catalog languages,
    Turkish included, and has no fast or accurate level.
  - Given the file's data, Vision applies its orientation metadata, so word boxes match the photo as
    displayed.
  - Measured on a generated two-paragraph page: about 0.4–0.5 s, 25 words per paragraph, and correct
    sentence extraction across line wraps.
- **Object:**
  - Run Vision **`ClassifyImageRequest`** on device and keep labels with confidence ≥ 0.3 (top 5).
  - The learner picks or corrects a label.
  - The active AI model returns the object's name in the chosen learning language (with
    article/gender where relevant), a translation into the native language and an example sentence.
  - Sending the photo itself to a vision-capable cloud model is **off by default**. It waits on
    spec open question 3.
- **Images:**
  - Only downscaled JPEG thumbnails (long edge ≤ 1024 px, quality 0.7) are stored, as
    `@Attribute(.externalStorage)`. Originals are not kept.
  - Images are attached only when the learner keeps "Save photo" on.
- **Live camera scanning** (`DataScannerViewController`) moves to v1.1. It is iOS/iPadOS only,
  needs A12 or later, and does not run on macOS or the Simulator. Photo-based capture covers all
  platforms first.

## Alternatives Considered
- **`RecognizeTextRequest` only:**
  - Returns lines, so sentences that wrap across lines must be stitched by hand.
  - Rejected: `RecognizeDocumentsRequest` provides paragraphs and words directly.
- **`VNDocumentCameraViewController`:**
  - Good page cropping, but iOS/iPadOS/Catalyst only and no word-level selection.
  - May still be used as the camera UI on iOS later.
- **Cloud OCR or cloud vision by default:**
  - Rejected for privacy and offline use.
- **Live Text interaction (`ImageAnalysisInteraction`):**
  - Gives selection for free, but not a reliable "tapped word + its sentence" hook on both
    platforms.
  - Rejected in favor of our own overlay.

## Consequences
- The same capture pipeline runs on iPhone, iPad and Mac, and can be unit-tested on the Mac host
  with generated images.
- Recognition quality depends on lighting and focus. The learner can always edit the term and the
  sentence.
- Object labels from the on-device classifier are English taxonomy identifiers (e.g. `cup`). The AI
  model turns them into the learner's languages, so object capture needs AI (on device or cloud).
- Photos synced through iCloud cost storage. Thumbnails keep this small, and photos are optional.

## Sources
- `RecognizeDocumentsRequest` and `DocumentObservation` (paragraphs, words, transcript):
  `Vision.swiftinterface`, macOS 26.2 SDK; https://developer.apple.com/documentation/vision
- `RecognizeTextRequest`, `RecognizedText.boundingBox(for:)`:
  https://developer.apple.com/documentation/vision/recognizetextrequest ,
  https://developer.apple.com/documentation/vision/recognizedtext/boundingbox(for:)
- `RecognizeDocumentsRequest` and its supported languages:
  https://developer.apple.com/documentation/vision/recognizedocumentsrequest ,
  https://developer.apple.com/documentation/vision/recognizedocumentsrequest/supportedrecognitionlanguages
- Thumbnails with ImageIO:
  https://developer.apple.com/documentation/imageio/cgimagesourcecreatethumbnailatindex(_:_:_:) ,
  https://developer.apple.com/documentation/imageio/kcgimagesourcethumbnailmaxpixelsize ,
  https://developer.apple.com/documentation/imageio/kcgimagesourcecreatethumbnailwithtransform
- `ClassifyImageRequest`: https://developer.apple.com/documentation/vision/classifyimagerequest
- `DataScannerViewController` requirements:
  https://developer.apple.com/documentation/visionkit/datascannerviewcontroller/issupported
- `VNDocumentCameraViewController`: https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller
- Measurements: local probe on macOS 26.5.2 (2026-10-04), reproduced by `VocabularyCaptureTests`.
