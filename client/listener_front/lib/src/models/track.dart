import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum CoverStyle {
  sky(Color(0xFF31C7E8)),
  eclipse(Color(0xFF0B0505)),
  mist(Color(0xFFE9F4F4)),
  monochrome(Color(0xFF151515)),
  street(Color(0xFF141414)),
  wave(Color(0xFF031011)),
  sunset(Color(0xFF20325B));

  const CoverStyle(this.base);

  final Color base;
}

class Track {
  const Track({
    required this.id,
    required this.number,
    required this.title,
    required this.length,
    required this.artist,
    required this.album,
    required this.releaseDate,
    required this.dateAdded,
    required this.plays,
    this.favorite = false,
    this.hasBadge = false,
    this.artwork,
    this.artworkId,
  });

  final String id;
  final String number;
  final String title;
  final String length;
  final String artist;
  final String album;
  final String releaseDate;
  final String dateAdded;
  final String plays;
  final bool favorite;
  final bool hasBadge;
  final Artwork? artwork;
  final int? artworkId;
}

class Artwork {
  const Artwork({
    required this.mimeType,
    required this.width,
    required this.height,
    required this.data,
  });

  final String mimeType;
  final int width;
  final int height;
  final Uint8List data;
}
