export interface VideoMessage {
  type: 'frame' | 'stop' | 'processed_frame' | 'completed' | 'error';
  data?: string;
  timestamp?: string;
  message?: string;
  output_path?: string;
  statistics?: {
    total_frames: number;
    fps: number;
    output_width: number;
    output_height: number;
  };
}

export interface CameraConfig {
  frameRate?: number;
  quality?: 'low' | 'medium' | 'high';
  width?: number;
  height?: number;
}

export interface WebSocketConfig {
  url: string;
  clientId: string;
}
