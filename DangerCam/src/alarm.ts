import { Audio } from 'expo-av';

const SAMPLE_RATE = 8000;
const DURATION = 2;
const NUM_SAMPLES = SAMPLE_RATE * DURATION;

function generateAlarmDataUri(): string {
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

  // Convert to base64 data URI
  let binary = '';
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return 'data:audio/wav;base64,' + btoa(binary);
}

let alarmSound: Audio.Sound | null = null;
let alarmWavUri: string | null = null;

export async function playAlarm(): Promise<void> {
  try {
    await stopAlarm();

    await Audio.setAudioModeAsync({
      playsInSilentModeIOS: true,
      staysActiveInBackground: false,
    });

    if (!alarmWavUri) {
      alarmWavUri = generateAlarmDataUri();
    }

    const { sound } = await Audio.Sound.createAsync({ uri: alarmWavUri });
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
