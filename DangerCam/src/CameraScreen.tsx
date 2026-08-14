import React, { useState, useRef, useEffect, useCallback } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  TextInput,
  ScrollView,
  Modal,
  SafeAreaView,
  Vibration,
  Dimensions,
  KeyboardAvoidingView,
  TouchableWithoutFeedback,
  Keyboard,
  Platform,
} from 'react-native';
import { CameraView, useCameraPermissions } from 'expo-camera';
import { StatusBar } from 'expo-status-bar';
import { analyzePhoto, AnalysisResult } from './claude';
import { playAlarm } from './alarm';

const DEFAULT_PROMPT =
  'Analyze this image for any potential dangers or safety hazards. ' +
  'If you detect something dangerous, include the word DANGER in your response. ' +
  'Otherwise, briefly describe what you see.';

export default function CameraScreen() {
  const [permission, requestPermission] = useCameraPermissions();
  const cameraRef = useRef<CameraView>(null);

  const [apiKey, setApiKey] = useState('');
  const [prompt, setPrompt] = useState(DEFAULT_PROMPT);
  const [intervalSec, setIntervalSec] = useState(10);
  const [isRunning, setIsRunning] = useState(false);
  const [responses, setResponses] = useState<AnalysisResult[]>([]);
  const [showSettings, setShowSettings] = useState(true);
  const [isDanger, setIsDanger] = useState(false);
  const [isAnalyzing, setIsAnalyzing] = useState(false);
  const [captureCount, setCaptureCount] = useState(0);
  const [error, setError] = useState<string | null>(null);

  const isAnalyzingRef = useRef(false);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const dangerTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const captureAndAnalyze = useCallback(async () => {
    if (isAnalyzingRef.current || !cameraRef.current || !apiKey) return;

    isAnalyzingRef.current = true;
    setIsAnalyzing(true);
    setError(null);

    try {
      const photo = await cameraRef.current.takePictureAsync({
        base64: true,
        quality: 0.3,
      });

      if (!photo?.base64) throw new Error('Failed to capture photo');

      setCaptureCount((c) => c + 1);
      const result = await analyzePhoto(photo.base64, apiKey, prompt);
      setResponses((prev) => [result, ...prev].slice(0, 50));

      if (result.isDanger) {
        setIsDanger(true);
        Vibration.vibrate([0, 500, 200, 500, 200, 500]);
        playAlarm();
        if (dangerTimeoutRef.current) clearTimeout(dangerTimeoutRef.current);
        dangerTimeoutRef.current = setTimeout(() => setIsDanger(false), 3000);
      }
    } catch (err: any) {
      setError(err.message || 'Unknown error');
    } finally {
      isAnalyzingRef.current = false;
      setIsAnalyzing(false);
    }
  }, [apiKey, prompt]);

  // Start/stop the capture interval
  useEffect(() => {
    if (isRunning && apiKey) {
      captureAndAnalyze();
      intervalRef.current = setInterval(captureAndAnalyze, intervalSec * 1000);
    }
    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
    };
  }, [isRunning, intervalSec, captureAndAnalyze, apiKey]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (dangerTimeoutRef.current) clearTimeout(dangerTimeoutRef.current);
    };
  }, []);

  // Permission not yet determined
  if (!permission) {
    return (
      <View style={styles.container}>
        <StatusBar style="light" />
      </View>
    );
  }

  // Permission denied
  if (!permission.granted) {
    return (
      <SafeAreaView style={styles.container}>
        <StatusBar style="light" />
        <View style={styles.permissionContainer}>
          <Text style={styles.permissionTitle}>Camera Access Required</Text>
          <Text style={styles.permissionText}>
            DangerCam needs camera access to capture and analyze photos.
          </Text>
          <TouchableOpacity
            onPress={requestPermission}
            style={styles.primaryButton}
          >
            <Text style={styles.primaryButtonText}>Grant Permission</Text>
          </TouchableOpacity>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <View style={styles.container}>
      <StatusBar style="light" />

      <CameraView ref={cameraRef} style={styles.camera} facing="back">
        {/* DANGER flash overlay */}
        {isDanger && (
          <View style={styles.dangerOverlay}>
            <Text style={styles.dangerText}>DANGER</Text>
          </View>
        )}

        {/* Top controls */}
        <SafeAreaView style={styles.topBar}>
          <TouchableOpacity
            onPress={() => setShowSettings(true)}
            style={styles.topButton}
          >
            <Text style={styles.topButtonText}>Settings</Text>
          </TouchableOpacity>

          <View style={styles.statusArea}>
            {isAnalyzing && <Text style={styles.statusDot}>Analyzing</Text>}
            {isRunning && !isAnalyzing && (
              <Text style={styles.statusIdle}>
                #{captureCount} — every {intervalSec}s
              </Text>
            )}
          </View>

          <TouchableOpacity
            onPress={() => setIsRunning(!isRunning)}
            style={[
              styles.topButton,
              isRunning ? styles.stopButton : styles.startButton,
            ]}
          >
            <Text style={styles.topButtonText}>
              {isRunning ? 'Stop' : 'Start'}
            </Text>
          </TouchableOpacity>
        </SafeAreaView>

        {/* Error banner */}
        {error && (
          <View style={styles.errorBanner}>
            <Text style={styles.errorText} numberOfLines={3}>
              {error}
            </Text>
            <TouchableOpacity onPress={() => setError(null)}>
              <Text style={styles.errorDismiss}>dismiss</Text>
            </TouchableOpacity>
          </View>
        )}

        {/* Response log */}
        <View style={styles.logContainer}>
          {responses.length === 0 && !isRunning && (
            <Text style={styles.logPlaceholder}>
              Tap Start to begin capturing and analyzing photos.
            </Text>
          )}
          <ScrollView style={styles.logScroll}>
            {responses.map((r, i) => (
              <View
                key={i}
                style={[
                  styles.logEntry,
                  r.isDanger && styles.logEntryDanger,
                ]}
              >
                <Text style={styles.logTime}>
                  {r.timestamp.toLocaleTimeString()}
                </Text>
                <Text
                  style={[
                    styles.logText,
                    r.isDanger && styles.logTextDanger,
                  ]}
                  numberOfLines={4}
                >
                  {r.text}
                </Text>
              </View>
            ))}
          </ScrollView>
        </View>
      </CameraView>

      {/* Settings modal */}
      <Modal visible={showSettings} animationType="slide" transparent>
        <TouchableWithoutFeedback onPress={Keyboard.dismiss}>
          <KeyboardAvoidingView
            style={styles.modalBackdrop}
            behavior={Platform.OS === 'ios' ? 'padding' : undefined}
          >
            <SafeAreaView style={styles.modalSafe}>
              <ScrollView
                contentContainerStyle={styles.modalScroll}
                keyboardShouldPersistTaps="handled"
              >
                <View style={styles.modal}>
                  <Text style={styles.modalTitle}>DangerCam Settings</Text>

                  <Text style={styles.label}>Anthropic API Key</Text>
                  <TextInput
                    style={styles.input}
                    value={apiKey}
                    onChangeText={setApiKey}
                    placeholder="sk-ant-api03-..."
                    placeholderTextColor="#666"
                    secureTextEntry
                    autoCapitalize="none"
                    autoCorrect={false}
                    returnKeyType="done"
                    onSubmitEditing={Keyboard.dismiss}
                  />

                  <Text style={styles.label}>Analysis Prompt</Text>
                  <TextInput
                    style={[styles.input, styles.promptInput]}
                    value={prompt}
                    onChangeText={setPrompt}
                    placeholder="What should Claude look for?"
                    placeholderTextColor="#666"
                    multiline
                    textAlignVertical="top"
                  />

                  <Text style={styles.label}>
                    Capture Interval: {intervalSec}s
                  </Text>
                  <View style={styles.stepperRow}>
                    <TouchableOpacity
                      onPress={() =>
                        setIntervalSec((v) =>
                          Math.max(3, v - (v > 10 ? 5 : 1)),
                        )
                      }
                      style={styles.stepperButton}
                    >
                      <Text style={styles.stepperButtonText}>-</Text>
                    </TouchableOpacity>

                    <View style={styles.stepperTrack}>
                      <View
                        style={[
                          styles.stepperFill,
                          {
                            width: `${((intervalSec - 3) / (120 - 3)) * 100}%`,
                          },
                        ]}
                      />
                    </View>

                    <TouchableOpacity
                      onPress={() =>
                        setIntervalSec((v) =>
                          Math.min(120, v + (v >= 10 ? 5 : 1)),
                        )
                      }
                      style={styles.stepperButton}
                    >
                      <Text style={styles.stepperButtonText}>+</Text>
                    </TouchableOpacity>
                  </View>
                  <Text style={styles.stepperHint}>
                    Range: 3s - 120s. Lower values use more API credits.
                  </Text>

                  <TouchableOpacity
                    onPress={() => {
                      Keyboard.dismiss();
                      if (apiKey.trim()) setShowSettings(false);
                    }}
                    style={[
                      styles.primaryButton,
                      !apiKey.trim() && styles.buttonDisabled,
                    ]}
                  >
                    <Text style={styles.primaryButtonText}>
                      {apiKey.trim() ? 'Done' : 'Enter API Key to Continue'}
                    </Text>
                  </TouchableOpacity>
                </View>
              </ScrollView>
            </SafeAreaView>
          </KeyboardAvoidingView>
        </TouchableWithoutFeedback>
      </Modal>
    </View>
  );
}

const { width: SCREEN_WIDTH } = Dimensions.get('window');

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000',
  },
  camera: {
    flex: 1,
  },

  // Permission screen
  permissionContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 32,
  },
  permissionTitle: {
    color: '#fff',
    fontSize: 22,
    fontWeight: '700',
    marginBottom: 12,
  },
  permissionText: {
    color: '#aaa',
    fontSize: 16,
    textAlign: 'center',
    marginBottom: 24,
  },

  // Top bar
  topBar: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingTop: 8,
    paddingBottom: 8,
  },
  topButton: {
    backgroundColor: 'rgba(0,0,0,0.5)',
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 8,
  },
  topButtonText: {
    color: '#fff',
    fontSize: 15,
    fontWeight: '600',
  },
  startButton: {
    backgroundColor: 'rgba(34,197,94,0.7)',
  },
  stopButton: {
    backgroundColor: 'rgba(239,68,68,0.7)',
  },
  statusArea: {
    flex: 1,
    alignItems: 'center',
  },
  statusDot: {
    color: '#fbbf24',
    fontSize: 13,
    fontWeight: '600',
  },
  statusIdle: {
    color: 'rgba(255,255,255,0.6)',
    fontSize: 13,
  },

  // DANGER overlay
  dangerOverlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(220,38,38,0.45)',
    justifyContent: 'center',
    alignItems: 'center',
    zIndex: 100,
  },
  dangerText: {
    color: '#fff',
    fontSize: 64,
    fontWeight: '900',
    letterSpacing: 8,
  },

  // Error
  errorBanner: {
    backgroundColor: 'rgba(220,38,38,0.85)',
    marginHorizontal: 12,
    marginTop: 4,
    padding: 10,
    borderRadius: 8,
    flexDirection: 'row',
    alignItems: 'center',
  },
  errorText: {
    color: '#fff',
    fontSize: 13,
    flex: 1,
  },
  errorDismiss: {
    color: '#fecaca',
    fontSize: 13,
    marginLeft: 8,
    textDecorationLine: 'underline',
  },

  // Response log
  logContainer: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    maxHeight: 220,
    backgroundColor: 'rgba(0,0,0,0.6)',
    borderTopLeftRadius: 12,
    borderTopRightRadius: 12,
    padding: 10,
  },
  logPlaceholder: {
    color: 'rgba(255,255,255,0.5)',
    fontSize: 14,
    textAlign: 'center',
    paddingVertical: 12,
  },
  logScroll: {
    flex: 1,
  },
  logEntry: {
    marginBottom: 8,
    padding: 8,
    backgroundColor: 'rgba(255,255,255,0.08)',
    borderRadius: 6,
    borderLeftWidth: 3,
    borderLeftColor: '#22c55e',
  },
  logEntryDanger: {
    borderLeftColor: '#ef4444',
    backgroundColor: 'rgba(239,68,68,0.15)',
  },
  logTime: {
    color: 'rgba(255,255,255,0.5)',
    fontSize: 11,
    marginBottom: 2,
  },
  logText: {
    color: '#e5e5e5',
    fontSize: 13,
    lineHeight: 18,
  },
  logTextDanger: {
    color: '#fca5a5',
    fontWeight: '600',
  },

  // Modal
  modalBackdrop: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.7)',
  },
  modalSafe: {
    flex: 1,
  },
  modalScroll: {
    flexGrow: 1,
    justifyContent: 'center',
  },
  modal: {
    marginHorizontal: 20,
    backgroundColor: '#1a1a2e',
    borderRadius: 16,
    padding: 24,
    maxHeight: '85%',
  },
  modalTitle: {
    color: '#fff',
    fontSize: 22,
    fontWeight: '700',
    marginBottom: 20,
    textAlign: 'center',
  },
  label: {
    color: '#aaa',
    fontSize: 13,
    fontWeight: '600',
    marginBottom: 6,
    marginTop: 14,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  input: {
    backgroundColor: '#16213e',
    color: '#fff',
    borderRadius: 8,
    padding: 12,
    fontSize: 15,
    borderWidth: 1,
    borderColor: '#2a2a4a',
  },
  promptInput: {
    height: 100,
  },

  // Stepper
  stepperRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  stepperButton: {
    width: 44,
    height: 44,
    borderRadius: 8,
    backgroundColor: '#16213e',
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#2a2a4a',
  },
  stepperButtonText: {
    color: '#fff',
    fontSize: 22,
    fontWeight: '600',
  },
  stepperTrack: {
    flex: 1,
    height: 6,
    backgroundColor: '#16213e',
    borderRadius: 3,
    overflow: 'hidden',
  },
  stepperFill: {
    height: '100%',
    backgroundColor: '#6366f1',
    borderRadius: 3,
  },
  stepperHint: {
    color: '#666',
    fontSize: 11,
    marginTop: 6,
  },

  // Buttons
  primaryButton: {
    backgroundColor: '#6366f1',
    paddingVertical: 14,
    borderRadius: 10,
    alignItems: 'center',
    marginTop: 24,
  },
  primaryButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '700',
  },
  buttonDisabled: {
    backgroundColor: '#333',
  },
});
