# ADR-005: Vision and Object Capture (Text + Objects)

**Status:** Accepted

**Date:** 2026-10-03

## Context

Users capture words from three sources:
1. **Text input:** Manual typing or pasting
2. **Book pages:** Photograph a physical book page, extract text via OCR, select words
3. **Objects:** Photograph an object (e.g., a coffee cup, a chair), optionally get AI description/translation

The system must provide seamless camera integration for both document scanning and general object capture.

## Decision

Use **Vision API + VisionKit** with two capture flows:

### Flow 1: Document Scanning (Books, articles)
- **VisionKit's `DataScannerViewController`** or **Vision framework's text recognition (`VNRecognizeTextRequest`)**
- Real-time text detection on camera feed
- User taps words they want to learn
- Stores: `(selectedWord, context: fullSentence, sourceLanguage, image: pagePhoto)`

### Flow 2: Object Capture (General photography)
- User photographs an object (furniture, food, animal, etc.)
- App shows the photo and asks: "What is this?" (optional)
- AI describes it in user's native language + target language
- User can add it as a word list item with the object photo as context

### Technology Choices

- **Text Recognition:** `VNRecognizeTextRequest` (Vision framework, iOS 13+) for offline OCR
- **Live Text:** Leverage iOS 16+ Live Text for in-app selection (user highlights text)
- **Camera permissions:** Request photo library + camera access on first use
- **Object recognition:** `VNClassificationRequest` for basic object identification; AI for detailed descriptions

## Consequences

- **Positive:**
  - Captures real-world learning context (the book page, the object itself)
  - No external API calls for OCR (Vision framework is on-device)
  - Rich learning memory: word + visual context
  - Accessible: VisionKit is built-in, no third-party dependencies

- **Negative:**
  - OCR quality depends on lighting, page angle, camera focus
  - Object recognition is basic without fine-tuning
  - Image storage increases iCloud sync data
  - User must manually refine auto-detected text

## Implementation Notes

- **Vision framework:** `VNRecognizeTextRequest` for batch OCR of captured images
- **Image compression:** Store thumbnails (not full resolution) in CloudKit to minimize sync
- **OCR fallback:** If recognition fails, show raw image + manual text entry option
- **Permissions:** Request camera + photo library on first use
- **Accessibility:** Ensure selected words are readable (text size, contrast)

## Alternative Considered

- **Third-party OCR (Tesseract, Cloud Vision API):** Rejected because it requires sending images to external servers, violates privacy principle

## Future Enhancements

- Real-time handwriting recognition (for handwritten notes)
- QR code scanning (to link to sources)
- Barcode scanning (to capture book ISBN)
