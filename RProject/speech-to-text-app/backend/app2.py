from flask import Flask, request, jsonify
import whisper
import librosa
import numpy as np
import tempfile

app = Flask(__name__)
model = whisper.load_model("base")

def transcribe_audio(file):
    with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as tmp:
        file.save(tmp)
        tmp_path = tmp.name
    audio = whisper.load_audio(tmp_path)
    audio = whisper.pad_or_trim(audio)
    mel = whisper.log_mel_spectrogram(audio).to(model.device)
    result = model.transcribe(audio)
    return result['text'], result['segments']

def calculate_wpm(transcript, duration):
    words = len(transcript.split())
    return words / (duration / 60)

@app.route('/analyze_multi', methods=['POST'])
def analyze_multi():
    files = request.files.getlist("files")
    if not files:
        return jsonify({"error": "No audio files provided"}), 400

    print(f"Received {len(files)} files: {[f.filename for f in files]}")  # Enhanced logging
    results = []
    for file in files:
        if not file.filename.lower().endswith(('.mp3', '.wav')):
            results.append({
                "filename": file.filename,
                "error": "Invalid file format. Only .mp3 and .wav are supported"
            })
            continue

        try:
            print(f"Processing file: {file.filename}")
            transcript, segments = transcribe_audio(file)
            file.seek(0)
            y, sr = librosa.load(file, sr=None)

            duration = librosa.get_duration(y=y, sr=sr)
            wpm = calculate_wpm(transcript, duration)
            mean_conf = np.mean([s.get("confidence", 0.9) for s in segments])

            results.append({
                "filename": file.filename,
                "transcript": transcript,
                "stats": {
                    "filename": file.filename,
                    "mean_wpm": wpm,
                    "mean_confidence": mean_conf
                }
            })
        except Exception as e:
            print(f"Error processing {file.filename}: {str(e)}")  # Log errors
            results.append({
                "filename": file.filename,
                "error": str(e)
            })

    return jsonify({"results": results})

if __name__ == '__main__':
    app.run(debug=True, port=5001)