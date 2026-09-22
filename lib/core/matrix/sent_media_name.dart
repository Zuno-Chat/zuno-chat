const sentVideoName = 'video.mp4';

String sentPhotoName(String mimeType) =>
    mimeType == 'image/png' ? 'photo.png' : 'photo.jpg';
