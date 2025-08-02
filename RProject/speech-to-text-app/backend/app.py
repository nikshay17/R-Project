from flask import Flask, request, jsonify
import whisper
import librosa
import numpy as np
import matplotlib.pyplot as plt
import os
import scipy.stats as stats
import base64
import io
from flask_cors import CORS
import logging
import numpy as np
# Setup
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)
model = whisper.load_model("base")
UPLOAD_FOLDER = "uploads"
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

def plot_to_base64():
    buf = io.BytesIO()
    plt.savefig(buf, format='png', bbox_inches='tight', dpi=100)
    plt.close()
    return base64.b64encode(buf.getvalue()).decode('utf-8')

def analyze_audio(filepath):
    try:
        audio, sr = librosa.load(filepath)
        result = model.transcribe(filepath)
        segments = result.get('segments', [])
        words = [w for seg in segments for w in seg['text'].split() if w.isalpha()]

        wpm_values = []
        speech_durations = []
        for seg in segments:
            if seg['end'] - seg['start'] > 0.1:
                word_count = len(seg['text'].split())
                duration = seg['end'] - seg['start']
                wpm_values.append((word_count / duration) * 60)
                speech_durations.append(duration)

        total_speech_duration = sum(speech_durations)
        silence_ratio = 1 - (total_speech_duration / segments[-1]['end']) if segments else 0

        confidences = [seg.get('confidence', 0.9) for seg in segments]
        confidence_metrics = {
            'high_confidence_ratio': sum(c > 0.9 for c in confidences)/len(confidences),
            'low_confidence_words': [seg['text'] for seg in segments if seg.get('confidence', 1) < 0.7]
        }

        avg_pause_duration = np.mean([segments[i+1]['start'] - segments[i]['end']
                                      for i in range(len(segments)-1)]) if len(segments) > 1 else 0

        unique_words = len(set(words))
        lexical_diversity = unique_words / len(words) if words else 0

        plots = {}

        plt.figure(figsize=(12,5))
        ends = [seg['end'] for seg in segments if seg['end']-seg['start'] > 0.1]
        plt.plot(ends, wpm_values, color='#4e79a7', linewidth=2)
        plt.axhline(y=np.mean(wpm_values), color='#e15759', linestyle='--')
        plt.fill_between(ends, np.mean(wpm_values)-10, np.mean(wpm_values)+10, alpha=0.1)
        plt.title("Speaking Rate Variability (WPM)\nwith Average Reference Line")
        plt.xlabel("Time (seconds)")
        plt.ylabel("Words Per Minute")
        plots["wpm_plot"] = plot_to_base64()

        plt.figure(figsize=(10,5))
        pauses = []
        confs = []
        for i in range(len(segments)-1):
            pause = segments[i+1]['start'] - segments[i]['end']
            pauses.append(pause)
            confs.append(np.mean([segments[i].get('confidence',0.9), 
                                   segments[i+1].get('confidence',0.9)]))
        plt.scatter(pauses, confs, alpha=0.6)
        plt.title("Pause Duration vs Confidence")
        plt.xlabel("Pause Duration (s)")
        plt.ylabel("Average Confidence")
        plots["pause_confidence_plot"] = plot_to_base64()

        word_lengths = [len(w) for w in words]
        plt.figure(figsize=(10,4))
        plt.hist2d(range(len(word_lengths)), word_lengths, bins=[30, 10], cmap='Blues')
        plt.colorbar(label='Word Count')
        plt.title("Word Length Distribution Over Time")
        plt.xlabel("Word Position in Transcript")
        plt.ylabel("Word Length")
        plots["vocab_heatmap"] = plot_to_base64()

        energy = librosa.feature.rms(y=audio)[0]
        energy_times = np.linspace(0, len(audio)/sr, len(energy))
        seg_energies = [np.mean(energy[(energy_times >= seg['start']) & (energy_times <= seg['end'])])
                        for seg in segments]

        plt.figure(figsize=(10,5))
        plt.scatter(seg_energies, [s.get('confidence',0.9) for s in segments], alpha=0.6)
        plt.title("Audio Energy vs Transcription Confidence")
        plt.xlabel("Average Segment Energy")
        plt.ylabel("Confidence Score")
        plots["energy_confidence_plot"] = plot_to_base64()

        return {
            "success": True,
            "transcript": result['text'],
            "stats": {
                "speech_metrics": {
                    "mean_wpm": round(np.mean(wpm_values), 1) if wpm_values else 0,
                    "wpm_variability": round(np.std(wpm_values), 1) if wpm_values else 0,
                    "silence_ratio": round(silence_ratio, 2),
                    "avg_pause_duration": round(avg_pause_duration, 2)
                },
                "confidence_metrics": confidence_metrics,
                "vocab_metrics": {
                    "unique_words": unique_words,
                    "lexical_diversity": round(lexical_diversity, 2),
                    "avg_word_length": round(np.mean([len(w) for w in words]), 1) if words else 0
                }
            },
            "plots": plots
        }

    except Exception as e:
        logger.error(f"Analysis failed: {str(e)}")
        return {"success": False, "error": str(e)}

@app.route('/analyze', methods=['POST'])
def analyze_endpoint():
    # Check if files were uploaded
    if not request.files:
        return jsonify({"error": "No files uploaded"}), 400

    # Handle both single file and multiple files upload
    files = []
    if 'files' in request.files:  # Case 1: Multiple files uploaded as list
        files = request.files.getlist('files')
    else:  # Case 2: Individual files (files1, files2, etc.)
        files = [request.files[key] for key in request.files if key.startswith('files')]

    if not files:
        return jsonify({"error": "No valid files selected"}), 400

    try:
        # Single file analysis
        if len(files) == 1:
            file = files[0]
            if file.filename == '':
                return jsonify({"error": "No selected file"}), 400

            filepath = os.path.join(UPLOAD_FOLDER, file.filename)
            file.save(filepath)
            result = analyze_audio(filepath)
            os.remove(filepath)
            
            if not result['success']:
                return jsonify(result), 400
            return jsonify(result)

        # Multi-file comparison (2-3 files)
        elif 2 <= len(files) <= 3:
            results = []
            for file in files:
                if file.filename == '':
                    continue

                filepath = os.path.join(UPLOAD_FOLDER, file.filename)
                file.save(filepath)
                res = analyze_audio(filepath)
                os.remove(filepath)
                
                if res['success']:
                    results.append({
                        "filename": file.filename,
                        "stats": res['stats'],
                        "transcript": res['transcript'][:500] + "..."
                    })

            if len(results) < 2:
                return jsonify({
                    "success": False,
                    "error": "Need at least 2 valid files for comparison"
                }), 400

            # Generate comparison plots
            plt.figure(figsize=(12,6))
            metrics = ['mean_wpm', 'wpm_variability', 'silence_ratio']
            for i, metric in enumerate(metrics):
                plt.subplot(1, len(metrics), i+1)
                plt.bar([r['filename'][:15] for r in results],
                        [r['stats']['speech_metrics'][metric] for r in results])
                plt.title(metric.replace('_', ' ').title())
                plt.xticks(rotation=45)
            plt.tight_layout()
            metrics_comparison = plot_to_base64()

            plt.figure(figsize=(10,5))
            x = [r['stats']['vocab_metrics']['lexical_diversity'] for r in results]
            y = [r['stats']['confidence_metrics']['high_confidence_ratio'] for r in results]
            plt.scatter(x, y)
            for i, r in enumerate(results):
                plt.annotate(r['filename'][:10], (x[i], y[i]))
            plt.title("Lexical Diversity vs Confidence")
            plt.xlabel("Lexical Diversity")
            plt.ylabel("High Confidence Ratio")
            vocab_conf_comparison = plot_to_base64()

            # Calculate ANOVA with proper error handling
            try:
                wpm_values = [[r['stats']['speech_metrics']['mean_wpm']] for r in results]
                if len(wpm_values) >= 2 and len(set(wpm[0] for wpm in wpm_values)) > 1:
                    _, pvalue = stats.f_oneway(*wpm_values)
                else:
                    pvalue = float('nan')
            except Exception as e:
                print(f"ANOVA calculation error: {str(e)}")
                pvalue = float('nan')

            return jsonify({
                "success": True,
                "comparison_plots": {
                    "metrics_comparison": metrics_comparison,
                    "vocab_conf_comparison": vocab_conf_comparison
                },
                "files": results,
                "anova_results": {
                    "wpm_pvalue": None if np.isnan(pvalue) else pvalue
                }
            })

        return jsonify({
            "success": False,
            "error": "Please upload 1-3 files only"
        }), 400

    except Exception as e:
        logger.error(f"Analysis failed: {str(e)}")
        return jsonify({
            "success": False,
            "error": f"Processing error: {str(e)}"
        }), 500

if __name__ == '__main__':
    app.run(port=5000, debug=True)