# Swift Package Dependencies

Before building, add the following Swift Package in Xcode:

## FluidAudio

1. Open `D Scribe.xcodeproj` in Xcode
2. Go to **File > Add Package Dependencies...**
3. Enter the URL: `https://github.com/FluidInference/FluidAudio.git`
4. Set version rule to **Up to Next Major Version** with minimum **0.12.4**
5. Click **Add Package**
6. When prompted, add the **FluidAudio** library to the **D Scribe** target
7. Build the project

## WhisperKit

1. Go to **File > Add Package Dependencies...**
2. Enter the URL: `https://github.com/argmaxinc/WhisperKit.git`
3. Set version rule to **Up to Next Major Version** with minimum **0.9.0**
4. Click **Add Package**
5. When prompted, add the **WhisperKit** library to the **D Scribe** target

Note: First run downloads the Silero VAD model and WhisperKit distil-large-v3 model from HuggingFace.
