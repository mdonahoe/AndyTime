import { Audio } from 'expo-av';
import * as FileSystem from 'expo-file-system';

const SAMPLE_RATE = 8000;
const DURATION = 2;
const NUM_SAMPLES = SAMPLE_RATE * DURATION;

function uint8ArrayToBase64(bytes: Uint8Array): string {
  const chars =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let result = '';
  for (let i = 0; i < bytes.length; i += 3) {
    const a = bytes[i];
    const b = i + 1 < bytes.length ? bytes[i + 1] : 0;
    const c = i + 2 < bytes.length ? bytes[i + 2] : 0;
    result += chars[a >> 2];
    result += chars[((a & 3) << 4) | (b >> 4)];
    result += i + 1 < bytes.length ? chars[((b & 15) << 2) | (c >> 6)] : '=';
    result += i + 2 < bytes.length ? chars[c & 63] : '=';
  }
  return result;
}

function generateAlarmWav(): Uint8Array {
  const dataSize = NUM_SAMPLES * 2; // 16-bit = 2 bytes per sample
  const buffer = new ArrayBuffer(44 + dataSize);
  const view = new DataView(buffer);
  const bytes = new Uint8Array(buffer);

  // RIFF header
  bytes.set([0x52, 0x49, 0x46, 0x46], 0); // "RIFF"
  view.setUint32(4, 36 + dataSize, true);
  bytes.set([0x57, 0x41, 0x56, 0x45], 8); // "WAVE"

  // fmt subchunk
  bytes.set([0x66, 0x6d, 0x74, 0x20], 12); // "fmt "
  view.setUint32(16, 16, true); // subchunk size
  view.setUint16(20, 1, true); // PCM format
  view.setUint16(22, 1, true); // mono
  view.setUint32(24, SAMPLE_RATE, true); // sample rate
  view.setUint32(28, SAMPLE_RATE * 2, true); // byte rate
  view.setUint16(32, 2, true); // block align
  view.setUint16(34, 16, true); // bits per sample

  // data subchunk
  bytes.set([0x64, 0x61, 0x74, 0x61], 36); // "data"
  view.setUint32(40, dataSize, true);

  // Generate alarm tone: alternating 880Hz / 660Hz every 0.25s
  for (let i = 0; i < NUM_SAMPLES; i++) {
    const t = i / SAMPLE_RATE;
    const freq = Math.floor(t / 0.25) % 2 === 0 ? 880 : 660;
    const amplitude = 0.7;
    const sample = Math.sin(2 * Math.PI * freq * t) * amplitude;
    const pcm = Math.max(-32768, Math.min(32767, Math.round(sample * 32767)));
    view.setInt16(44 + i * 2, pcm, true);
  }

  return bytes;
}

let alarmSound: Audio.Sound | null = null;
let alarmFileUri: string | null = null;

async function ensureAlarmFile(): Promise<string> {
  if (alarmFileUri) return alarmFileUri;

  const wavBytes = generateAlarmWav();
  const base64 = uint8ArrayToBase64(wavBytes);
  const uri = FileSystem.cacheDirectory + 'alarm.wav';

  await FileSystem.writeAsStringAsync(uri, base64, {
    encoding: FileSystem.EncodingType.Base64,
  });

  alarmFileUri = uri;
  return uri;
}

export async function playAlarm(): Promise<void> {
  try {
    await stopAlarm();

    await Audio.setAudioModeAsync({
      playsInSilentModeIOS: true,
      staysActiveInBackground: false,
    });

    const uri = await ensureAlarmFile();
    const { sound } = await Audio.Sound.createAsync({ uri });
    alarmSound = sound;
    await sound.playAsync();

    // Auto-cleanup after playback completes
    sound.setOnPlaybackStatusUpdate((status) => {
      if (status.isLoaded && status.didJustFinish) {
        sound.unloadAsync().catch(() => {});
        if (alarmSound === sound) alarmSound = null;
      }
    });
  } catch (error) {
    console.error('Failed to play alarm:', error);
  }
}

export async function stopAlarm(): Promise<void> {
  try {
    if (alarmSound) {
      await alarmSound.stopAsync();
      await alarmSound.unloadAsync();
      alarmSound = null;
    }
  } catch {}
}
