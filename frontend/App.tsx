import React from 'react';
import { SafeAreaView, StyleSheet, View, TextInput, Button } from 'react-native';
import VideoStreamer from './src/components/VideoStreamer';
import { CameraConfig } from './src/types/video';

export default function App() {
  const [wsUrl, setWsUrl] = React.useState('ws://localhost:8000/ws/device1');
  const [clientId, setClientId] = React.useState('device1');
  const [isConnected, setIsConnected] = React.useState(false);
  const [currentStreamer, setCurrentStreamer] = React.useState<React.ReactNode>(null);

  const cameraConfig: CameraConfig = {
    frameRate: 30,
    quality: 'medium',
    width: 1280,
    height: 720,
  };

  const handleConnect = () => {
    setIsConnected(true);
    setCurrentStreamer(
      <VideoStreamer
        wsUrl={wsUrl}
        clientId={clientId}
        cameraConfig={cameraConfig}
      />
    );
  };

  return (
    <SafeAreaView style={styles.container}>
      {!isConnected ? (
        <View style={styles.formContainer}>
          <TextInput
            style={styles.input}
            placeholder="WebSocket URL"
            value={wsUrl}
            onChangeText={setWsUrl}
          />
          <TextInput
            style={styles.input}
            placeholder="Client ID"
            value={clientId}
            onChangeText={setClientId}
          />
          <Button title="Connect" onPress={handleConnect} />
        </View>
      ) : (
        currentStreamer
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000',
  },
  formContainer: {
    flex: 1,
    justifyContent: 'center',
    padding: 20,
  },
  input: {
    height: 50,
    borderColor: '#666',
    borderWidth: 1,
    borderRadius: 8,
    marginBottom: 15,
    paddingHorizontal: 15,
    color: 'white',
    fontSize: 16,
  },
});
