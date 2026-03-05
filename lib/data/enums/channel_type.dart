enum ChannelType {
  text,
  voice;

  static ChannelType fromString(String value) {
    switch (value) {
      case 'voice':
        return ChannelType.voice;
      default:
        return ChannelType.text;
    }
  }

  String toJson() => name;
}
