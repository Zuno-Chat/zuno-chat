const sentVideoName = 'video.mp4';

String sentPhotoName(String mimeType) => switch (mimeType) {
  'image/png' => 'photo.png',
  'image/gif' => 'photo.gif',
  'image/webp' => 'photo.webp',
  _ => 'photo.jpg',
};
