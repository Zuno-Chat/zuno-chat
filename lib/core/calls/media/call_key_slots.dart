const keyRingSize = 256;

int senderKeySlot(int gen) => (gen - 1) % keyRingSize;
