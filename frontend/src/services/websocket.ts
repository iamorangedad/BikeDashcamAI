import { WebSocketConfig, VideoMessage } from '../types/video';

class WebSocketService {
  private ws: WebSocket | null = null;
  private config: WebSocketConfig;
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 5;
  private reconnectDelay = 3000;
  private messageHandlers: ((message: VideoMessage) => void)[] = [];
  private connectionHandlers: (() => void)[] = [];
  private errorHandlers: ((error: Event) => void)[] = [];
  private closeHandlers: (() => void)[] = [];

  constructor(config: WebSocketConfig) {
    this.config = config;
  }

  connect(): void {
    try {
      this.ws = new WebSocket(this.config.url);

      this.ws.onopen = () => {
        console.log('WebSocket connected');
        this.reconnectAttempts = 0;
        this.connectionHandlers.forEach(handler => handler());
      };

      this.ws.onmessage = (event) => {
        try {
          const message: VideoMessage = JSON.parse(event.data);
          this.messageHandlers.forEach(handler => handler(message));
        } catch (error) {
          console.error('Error parsing WebSocket message:', error);
        }
      };

      this.ws.onerror = (error) => {
        console.error('WebSocket error:', error);
        this.errorHandlers.forEach(handler => handler(error));
      };

      this.ws.onclose = () => {
        console.log('WebSocket closed');
        this.closeHandlers.forEach(handler => handler());

        if (this.reconnectAttempts < this.maxReconnectAttempts) {
          this.reconnectAttempts++;
          console.log(`Reconnecting... Attempt ${this.reconnectAttempts}`);
          setTimeout(() => this.connect(), this.reconnectDelay);
        }
      };

    } catch (error) {
      console.error('Error connecting to WebSocket:', error);
    }
  }

  sendFrame(base64Data: string): void {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      const message: VideoMessage = {
        type: 'frame',
        data: base64Data
      };
      this.ws.send(JSON.stringify(message));
    }
  }

  stopStreaming(): void {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      const message: VideoMessage = {
        type: 'stop'
      };
      this.ws.send(JSON.stringify(message));
    }
  }

  onMessage(handler: (message: VideoMessage) => void): void {
    this.messageHandlers.push(handler);
  }

  onConnect(handler: () => void): void {
    this.connectionHandlers.push(handler);
  }

  onError(handler: (error: Event) => void): void {
    this.errorHandlers.push(handler);
  }

  onClose(handler: () => void): void {
    this.closeHandlers.push(handler);
  }

  disconnect(): void {
    if (this.ws) {
      this.reconnectAttempts = this.maxReconnectAttempts;
      this.ws.close();
      this.ws = null;
    }
  }

  isConnected(): boolean {
    return this.ws !== null && this.ws.readyState === WebSocket.OPEN;
  }
}

export default WebSocketService;
