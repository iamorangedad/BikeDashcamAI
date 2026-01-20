import React, { useEffect, useRef, useState } from 'react';
import { View, StyleSheet, TouchableOpacity, Text } from 'react-native';
import { Camera } from 'expo-camera';
import { CameraConfig } from '../types/video';

interface CameraViewProps {
  onFrameCapture?: (data: string) => void;
  isStreaming?: boolean;
  config?: CameraConfig;
}

const CameraView: React.FC<CameraViewProps> = ({
  onFrameCapture,
  isStreaming = false,
  config = {}
}) => {
  const [hasPermission, setHasPermission] = useState<boolean | null>(null);
  const [type, setType] = useState(Camera.Constants.Type.back);
  const cameraRef = useRef<Camera | null>(null);
  const intervalRef = useRef<NodeJS.Timeout | null>(null);

  const frameRate = config.frameRate || 30;
  const quality = config.quality || 'medium';

  useEffect(() => {
    (async () => {
      const { status } = await Camera.requestCameraPermissionsAsync();
      setHasPermission(status === 'granted');
    })();

    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
      }
    };
  }, []);

  useEffect(() => {
    if (isStreaming && hasPermission) {
      startFrameCapture();
    } else {
      stopFrameCapture();
    }

    return () => stopFrameCapture();
  }, [isStreaming, hasPermission]);

  const startFrameCapture = () => {
    const intervalMs = 1000 / frameRate;
    intervalRef.current = setInterval(async () => {
      if (cameraRef.current && onFrameCapture) {
        try {
          const photo = await cameraRef.current.takePictureAsync({
            quality: quality === 'high' ? 1 : quality === 'medium' ? 0.5 : 0.1,
            base64: true,
            skipProcessing: true
          });

          if (photo.base64) {
            onFrameCapture(photo.base64);
          }
        } catch (error) {
          console.error('Error capturing frame:', error);
        }
      }
    }, intervalMs);
  };

  const stopFrameCapture = () => {
    if (intervalRef.current) {
      clearInterval(intervalRef.current);
      intervalRef.current = null;
    }
  };

  const toggleCameraType = () => {
    setType(
      type === Camera.Constants.Type.back
        ? Camera.Constants.Type.front
        : Camera.Constants.Type.back
    );
  };

  if (hasPermission === null) {
    return <View style={styles.container} />;
  }

  if (hasPermission === false) {
    return (
      <View style={styles.container}>
        <Text style={styles.text}>No access to camera</Text>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <Camera
        ref={cameraRef}
        style={styles.camera}
        type={type}
        autoFocus={Camera.Constants.AutoFocus.on}
      />
      <View style={styles.buttonContainer}>
        <TouchableOpacity style={styles.button} onPress={toggleCameraType}>
          <Text style={styles.text}>Flip Camera</Text>
        </TouchableOpacity>
      </View>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: 'black',
  },
  camera: {
    flex: 1,
  },
  buttonContainer: {
    position: 'absolute',
    bottom: 20,
    left: 0,
    right: 0,
    alignItems: 'center',
  },
  button: {
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    padding: 10,
    borderRadius: 5,
  },
  text: {
    color: 'white',
    fontSize: 16,
  },
});

export default CameraView;
