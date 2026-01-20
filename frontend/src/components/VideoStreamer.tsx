import React, { useState, useEffect, useCallback } from 'react';
import { View, StyleSheet, TouchableOpacity, Text, SafeAreaView, ScrollView, Image } from 'react-native';
import CameraView from './CameraView';
import WebSocketService, { VideoMessage } from '../services/websocket';
import { CameraConfig } from '../types/video';

interface VideoStreamerProps {
  wsUrl: string;
  clientId: string;
  cameraConfig?: CameraConfig;
}

const VideoStreamer: React.FC<VideoStreamerProps> = ({
  wsUrl,
  clientId,
  cameraConfig = {}
}) => {
  const [isStreaming, setIsStreaming] = useState(false);
  const [isConnected, setIsConnected] = useState(false);
  const [processedFrames, setProcessedFrames] = useState<string[]>([]);
  const [stats, setStats] = useState<any>(null);
  const [error, setError] = useState<string | null>(null);
  const wsService = useRef<WebSocketService | null>(null);

  useEffect(() => {
    wsService.current = new WebSocketService({ url: wsUrl, clientId });

    wsService.current.onConnect(() => {
      setIsConnected(true);
      setError(null);
    });

    wsService.current.onError(() => {
      setIsConnected(false);
      setError('Connection error');
    });

    wsService.current.onClose(() => {
      setIsConnected(false);
      setIsStreaming(false);
    });

    wsService.current.onMessage((message: VideoMessage) => {
      switch (message.type) {
        case 'processed_frame':
          if (message.data) {
            setProcessedFrames(prev => [...prev.slice(-9), `data:image/jpeg;base64,${message.data}`]);
          }
          break;
        case 'completed':
          if (message.statistics) {
            setStats(message.statistics);
          }
          setIsStreaming(false);
          break;
        case 'error':
          setError(message.message || 'Processing error');
          setIsStreaming(false);
          break;
      }
    });

    wsService.current.connect();

    return () => {
      if (wsService.current) {
        wsService.current.disconnect();
      }
    };
  }, [wsUrl, clientId]);

  const handleFrameCapture = useCallback((base64Data: string) => {
    if (wsService.current && isConnected) {
      wsService.current.sendFrame(base64Data);
    }
  }, [isConnected]);

  const toggleStreaming = () => {
    if (!isConnected) {
      setError('Not connected to server');
      return;
    }

    const newStreamingState = !isStreaming;
    setIsStreaming(newStreamingState);

    if (!newStreamingState && wsService.current) {
      wsService.current.stopStreaming();
    }
  };

  const clearFrames = () => {
    setProcessedFrames([]);
  };

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView style={styles.scrollView}>
        <View style={styles.statusContainer}>
          <Text style={[
            styles.statusText,
            { color: isConnected ? 'green' : 'red' }
          ]}>
            {isConnected ? 'Connected' : 'Disconnected'}
          </Text>
          <Text style={styles.statusText}>
            {isStreaming ? 'Streaming' : 'Stopped'}
          </Text>
        </View>

        {error && (
          <View style={styles.errorContainer}>
            <Text style={styles.errorText}>{error}</Text>
          </View>
        )}

        <CameraView
          isStreaming={isStreaming}
          onFrameCapture={handleFrameCapture}
          config={cameraConfig}
        />

        <View style={styles.controlsContainer}>
          <TouchableOpacity
            style={[
              styles.button,
              styles.primaryButton,
              !isConnected && styles.disabledButton
            ]}
            onPress={toggleStreaming}
            disabled={!isConnected}
          >
            <Text style={styles.buttonText}>
              {isStreaming ? 'Stop' : 'Start Streaming'}
            </Text>
          </TouchableOpacity>

          <TouchableOpacity
            style={[styles.button, styles.secondaryButton]}
            onPress={clearFrames}
          >
            <Text style={styles.buttonText}>Clear Frames</Text>
          </TouchableOpacity>
        </View>

        {processedFrames.length > 0 && (
          <View style={styles.framesContainer}>
            <Text style={styles.framesTitle}>Processed Frames ({processedFrames.length})</Text>
            <ScrollView horizontal style={styles.framesScroll}>
              {processedFrames.map((frame, index) => (
                <Image
                  key={index}
                  source={{ uri: frame }}
                  style={styles.frameImage}
                />
              ))}
            </ScrollView>
          </View>
        )}

        {stats && (
          <View style={styles.statsContainer}>
            <Text style={styles.statsTitle}>Statistics</Text>
            <Text style={styles.statsText}>Total Frames: {stats.total_frames}</Text>
            <Text style={styles.statsText}>FPS: {stats.fps}</Text>
            <Text style={styles.statsText}>Resolution: {stats.output_width}x{stats.output_height}</Text>
          </View>
        )}
      </ScrollView>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000',
  },
  scrollView: {
    flex: 1,
  },
  statusContainer: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    padding: 10,
    backgroundColor: '#1a1a1a',
  },
  statusText: {
    color: 'white',
    fontSize: 16,
    fontWeight: 'bold',
  },
  errorContainer: {
    backgroundColor: 'red',
    padding: 10,
    margin: 10,
    borderRadius: 5,
  },
  errorText: {
    color: 'white',
    textAlign: 'center',
  },
  controlsContainer: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    padding: 20,
    backgroundColor: '#1a1a1a',
  },
  button: {
    padding: 15,
    borderRadius: 10,
    minWidth: 150,
    alignItems: 'center',
  },
  primaryButton: {
    backgroundColor: '#007AFF',
  },
  secondaryButton: {
    backgroundColor: '#34C759',
  },
  disabledButton: {
    backgroundColor: '#666',
  },
  buttonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: 'bold',
  },
  framesContainer: {
    padding: 10,
    backgroundColor: '#1a1a1a',
    marginTop: 10,
  },
  framesTitle: {
    color: 'white',
    fontSize: 18,
    fontWeight: 'bold',
    marginBottom: 10,
  },
  framesScroll: {
    flexDirection: 'row',
  },
  frameImage: {
    width: 120,
    height: 90,
    marginRight: 10,
    borderRadius: 5,
  },
  statsContainer: {
    padding: 15,
    backgroundColor: '#1a1a1a',
    marginTop: 10,
    marginBottom: 20,
  },
  statsTitle: {
    color: 'white',
    fontSize: 18,
    fontWeight: 'bold',
    marginBottom: 10,
  },
  statsText: {
    color: 'white',
    fontSize: 14,
    marginBottom: 5,
  },
});

export default VideoStreamer;
