// DangerCam — single-file version for Expo Snack
// Paste this into App.js at https://snack.expo.dev
//
// Required Snack dependencies (add in the sidebar):
//   expo-camera  ~16.0.0
//   expo-av      ~15.0.0

import React, { useState, useRef, useEffect, useCallback } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  TextInput,
  ScrollView,
  Modal,
  Vibration,
  SafeAreaView,
  StatusBar,
  KeyboardAvoidingView,
  TouchableWithoutFeedback,
  Keyboard,
  Platform,
} from 'react-native';
import { CameraView, useCameraPermissions } from 'expo-camera';
import { Audio } from 'expo-av';

// ─── Claude API ──────────────────────────────────────────────────────
const DEFAULT_PROMPT =
  'Analyze this image for any potential dangers or safety hazards. ' +
  'If you detect something dangerous, include the word DANGER in your response. ' +
  'Otherwise, briefly describe what you see.';

async function analyzePhoto(base64Image, apiKey, prompt) {
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
      'anthropic-dangerous-direct-browser-access': 'true',
    },
    body: JSON.stringify({
      model: 'claude-sonnet-4-20250514',
      max_tokens: 1024,
      messages: [
        {
          role: 'user',
          content: [
            {
              type: 'image',
              source: { type: 'base64', media_type: 'image/jpeg', data: base64Image },
            },
            { type: 'text', text: prompt },
          ],
        },
      ],
    }),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error('API ' + res.status + ': ' + body);
  }

  const data = await res.json();
  const text =
    (data.content || [])
      .filter((b) => b.type === 'text')
      .map((b) => b.text)
      .join('\n');

  return {
    text,
    isDanger: text.toUpperCase().includes('DANGER'),
    timestamp: new Date(),
  };
}

// ─── Alarm ───────────────────────────────────────────────────────────
let alarmSound = null;
let alarmWavUri = null;

function generateAlarmDataUri() {
  if (alarmWavUri) return alarmWavUri;

  const sampleRate = 8000;
  const duration = 2;
  const numSamples = sampleRate * duration;
  const bitsPerSample = 16;
  const byteRate = sampleRate * (bitsPerSample / 8);
  const dataSize = numSamples * (bitsPerSample / 8);
  const fileSize = 36 + dataSize;

  const buf = new ArrayBuffer(44 + dataSize);
  const view = new DataView(buf);

  const writeStr = (off, s) => {
    for (let i = 0; i < s.length; i++) view.setUint8(off + i, s.charCodeAt(i));
  };

  writeStr(0, 'RIFF');
  view.setUint32(4, fileSize, true);
  writeStr(8, 'WAVE');
  writeStr(12, 'fmt ');
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, byteRate, true);
  view.setUint16(32, bitsPerSample / 8, true);
  view.setUint16(34, bitsPerSample, true);
  writeStr(36, 'data');
  view.setUint32(40, dataSize, true);

  const amp = 0.7;
  for (let i = 0; i < numSamples; i++) {
    const t = i / sampleRate;
    const freq = Math.floor(t / 0.25) % 2 === 0 ? 880 : 660;
    const sample = Math.sin(2 * Math.PI * freq * t) * amp;
    view.setInt16(44 + i * 2, sample * 32767, true);
  }

  const bytes = new Uint8Array(buf);
  let binary = '';
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  alarmWavUri = 'data:audio/wav;base64,' + btoa(binary);
  return alarmWavUri;
}

async function playAlarm() {
  try {
    await Audio.setAudioModeAsync({
      playsInSilentModeIOS: true,
      staysActiveInBackground: false,
    });
    const uri = generateAlarmDataUri();
    const { sound } = await Audio.Sound.createAsync({ uri });
    alarmSound = sound;
    sound.setOnPlaybackStatusUpdate((status) => {
      if (status.didJustFinish) sound.unloadAsync();
    });
    await sound.playAsync();
  } catch (e) {
    console.warn('Alarm error:', e);
  }
}

async function stopAlarm() {
  if (alarmSound) {
    try {
      await alarmSound.stopAsync();
      await alarmSound.unloadAsync();
    } catch (e) {}
    alarmSound = null;
  }
}

// ─── Main App ────────────────────────────────────────────────────────
export default function App() {
  const [permission, requestPermission] = useCameraPermissions();
  const cameraRef = useRef(null);
  const intervalRef = useRef(null);

  const [apiKey, setApiKey] = useState('');
  const [prompt, setPrompt] = useState(DEFAULT_PROMPT);
  const [intervalSec, setIntervalSec] = useState(10);
  const [isRunning, setIsRunning] = useState(false);
  const [responses, setResponses] = useState([]);
  const [showSettings, setShowSettings] = useState(false);
  const [isDanger, setIsDanger] = useState(false);
  const [isAnalyzing, setIsAnalyzing] = useState(false);
  const [captureCount, setCaptureCount] = useState(0);
  const [error, setError] = useState(null);

  // ── capture + analyze ──
  const captureAndAnalyze = useCallback(async () => {
    if (!cameraRef.current || isAnalyzing) return;
    try {
      setIsAnalyzing(true);
      const photo = await cameraRef.current.takePictureAsync({
        base64: true,
        quality: 0.3,
      });
      if (!photo || !photo.base64) throw new Error('No image data');

      setCaptureCount((c) => c + 1);
      const result = await analyzePhoto(photo.base64, apiKey, prompt);

      setResponses((prev) => [result, ...prev].slice(0, 50));
      if (result.isDanger) {
        setIsDanger(true);
        Vibration.vibrate([0, 500, 200, 500, 200, 500]);
        playAlarm();
        setTimeout(() => setIsDanger(false), 3000);
      }
      setError(null);
    } catch (e) {
      setError(e.message || 'Unknown error');
    } finally {
      setIsAnalyzing(false);
    }
  }, [apiKey, prompt, isAnalyzing]);

  // ── start / stop loop ──
  const toggleRunning = useCallback(() => {
    if (isRunning) {
      if (intervalRef.current) clearInterval(intervalRef.current);
      intervalRef.current = null;
      setIsRunning(false);
      stopAlarm();
    } else {
      if (!apiKey) {
        setShowSettings(true);
        return;
      }
      setIsRunning(true);
      captureAndAnalyze();
      intervalRef.current = setInterval(captureAndAnalyze, intervalSec * 1000);
    }
  }, [isRunning, apiKey, intervalSec, captureAndAnalyze]);

  useEffect(() => {
    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current);
      stopAlarm();
    };
  }, []);

  // ── permission gate ──
  if (!permission) return <View style={s.container} />;
  if (!permission.granted) {
    return (
      <View style={s.center}>
        <Text style={s.permText}>Camera access is required</Text>
        <TouchableOpacity style={s.btn} onPress={requestPermission}>
          <Text style={s.btnText}>Grant Permission</Text>
        </TouchableOpacity>
      </View>
    );
  }

  // ── time format helper ──
  const fmt = (d) =>
    d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });

  // ── render ──
  return (
    <SafeAreaView style={s.container}>
      <StatusBar barStyle="light-content" />

      {/* ── Top bar ── */}
      <View style={s.topBar}>
        <TouchableOpacity onPress={() => setShowSettings(true)}>
          <Text style={s.icon}>{'\u2699'}</Text>
        </TouchableOpacity>
        <Text style={s.status}>
          {isAnalyzing ? 'Analyzing...' : isRunning ? 'Running \u00B7 ' + captureCount : 'Idle'}
        </Text>
        <TouchableOpacity
          style={[s.btn, isRunning ? s.btnStop : s.btnStart]}
          onPress={toggleRunning}
        >
          <Text style={s.btnText}>{isRunning ? 'Stop' : 'Start'}</Text>
        </TouchableOpacity>
      </View>

      {/* ── Camera ── */}
      <View style={s.cameraWrap}>
        <CameraView ref={cameraRef} style={s.camera} facing="back" />
        {isDanger && (
          <View style={s.dangerOverlay}>
            <Text style={s.dangerText}>DANGER</Text>
          </View>
        )}
      </View>

      {/* ── Error ── */}
      {error && (
        <TouchableOpacity style={s.errorBar} onPress={() => setError(null)}>
          <Text style={s.errorText} numberOfLines={2}>
            {error}
          </Text>
        </TouchableOpacity>
      )}

      {/* ── Log ── */}
      <ScrollView style={s.log}>
        {responses.map((r, i) => (
          <View key={i} style={[s.logEntry, r.isDanger && s.logDanger]}>
            <Text style={s.logTime}>{fmt(r.timestamp)}</Text>
            <Text style={s.logText}>{r.text}</Text>
          </View>
        ))}
      </ScrollView>

      {/* ── Settings modal ── */}
      <Modal visible={showSettings} animationType="slide" transparent>
        <TouchableWithoutFeedback onPress={Keyboard.dismiss}>
          <KeyboardAvoidingView
            style={s.modalBg}
            behavior={Platform.OS === 'ios' ? 'padding' : undefined}
          >
            <ScrollView
              contentContainerStyle={s.modalScroll}
              keyboardShouldPersistTaps="handled"
            >
              <View style={s.modal}>
                <Text style={s.modalTitle}>Settings</Text>

                <Text style={s.label}>Anthropic API Key</Text>
                <TextInput
                  style={s.input}
                  value={apiKey}
                  onChangeText={setApiKey}
                  placeholder="sk-ant-..."
                  placeholderTextColor="#666"
                  secureTextEntry
                  autoCapitalize="none"
                  returnKeyType="done"
                  onSubmitEditing={Keyboard.dismiss}
                />

                <Text style={s.label}>Prompt</Text>
                <TextInput
                  style={[s.input, { height: 100 }]}
                  value={prompt}
                  onChangeText={setPrompt}
                  multiline
                  placeholderTextColor="#666"
                />

                <Text style={s.label}>Interval: {intervalSec}s</Text>
                <View style={s.stepper}>
                  <TouchableOpacity
                    style={s.stepBtn}
                    onPress={() => setIntervalSec((v) => Math.max(3, v - 1))}
                  >
                    <Text style={s.stepBtnText}>{'\u2212'}</Text>
                  </TouchableOpacity>
                  <View style={s.sliderTrack}>
                    <View
                      style={[s.sliderFill, { width: ((intervalSec - 3) / 117) * 100 + '%' }]}
                    />
                  </View>
                  <TouchableOpacity
                    style={s.stepBtn}
                    onPress={() => setIntervalSec((v) => Math.min(120, v + 1))}
                  >
                    <Text style={s.stepBtnText}>+</Text>
                  </TouchableOpacity>
                </View>

                <TouchableOpacity
                  style={[s.btn, { marginTop: 20, alignSelf: 'center', paddingHorizontal: 40 }]}
                  onPress={() => setShowSettings(false)}
                >
                  <Text style={s.btnText}>Done</Text>
                </TouchableOpacity>
              </View>
            </ScrollView>
          </KeyboardAvoidingView>
        </TouchableWithoutFeedback>
      </Modal>
    </SafeAreaView>
  );
}

// ─── Styles ──────────────────────────────────────────────────────────
const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#000' },
  center: { flex: 1, backgroundColor: '#000', justifyContent: 'center', alignItems: 'center' },
  permText: { color: '#fff', fontSize: 18, marginBottom: 16 },

  topBar: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 12,
    paddingVertical: 8,
    backgroundColor: '#111',
  },
  icon: { fontSize: 26, color: '#aaa' },
  status: { color: '#ccc', fontSize: 14 },

  btn: {
    backgroundColor: '#6366f1',
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 8,
  },
  btnStart: { backgroundColor: '#22c55e' },
  btnStop: { backgroundColor: '#ef4444' },
  btnText: { color: '#fff', fontWeight: '700', fontSize: 14 },

  cameraWrap: { flex: 1, position: 'relative' },
  camera: { flex: 1 },

  dangerOverlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(239,68,68,0.55)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  dangerText: { color: '#fff', fontSize: 64, fontWeight: '900' },

  errorBar: {
    backgroundColor: '#dc2626',
    paddingHorizontal: 12,
    paddingVertical: 6,
  },
  errorText: { color: '#fff', fontSize: 12 },

  log: { maxHeight: 180, backgroundColor: '#111' },
  logEntry: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#333',
  },
  logDanger: { backgroundColor: 'rgba(239,68,68,0.15)' },
  logTime: { color: '#888', fontSize: 11, marginBottom: 2 },
  logText: { color: '#ddd', fontSize: 13 },

  modalBg: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.7)',
  },
  modalScroll: {
    flexGrow: 1,
    justifyContent: 'center',
    padding: 20,
  },
  modal: {
    backgroundColor: '#1a1a2e',
    borderRadius: 16,
    padding: 24,
  },
  modalTitle: { color: '#fff', fontSize: 22, fontWeight: '700', marginBottom: 16 },
  label: { color: '#aaa', fontSize: 13, marginTop: 12, marginBottom: 4 },
  input: {
    backgroundColor: '#0f0f23',
    color: '#fff',
    borderRadius: 8,
    padding: 10,
    fontSize: 14,
    borderWidth: 1,
    borderColor: '#333',
  },

  stepper: { flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: 4 },
  stepBtn: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: '#6366f1',
    justifyContent: 'center',
    alignItems: 'center',
  },
  stepBtnText: { color: '#fff', fontSize: 20, fontWeight: '700' },
  sliderTrack: {
    flex: 1,
    height: 6,
    backgroundColor: '#333',
    borderRadius: 3,
    overflow: 'hidden',
  },
  sliderFill: { height: 6, backgroundColor: '#6366f1', borderRadius: 3 },
});
