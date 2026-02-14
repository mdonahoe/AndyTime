export interface AnalysisResult {
  text: string;
  isDanger: boolean;
  timestamp: Date;
}

export async function analyzePhoto(
  base64Image: string,
  apiKey: string,
  prompt: string,
): Promise<AnalysisResult> {
  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
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
              source: {
                type: 'base64',
                media_type: 'image/jpeg',
                data: base64Image,
              },
            },
            {
              type: 'text',
              text: prompt,
            },
          ],
        },
      ],
    }),
  });

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(`API error ${response.status}: ${errorBody}`);
  }

  const data = await response.json();
  const text: string = data.content?.[0]?.text ?? 'No response';

  return {
    text,
    isDanger: text.toUpperCase().includes('DANGER'),
    timestamp: new Date(),
  };
}
