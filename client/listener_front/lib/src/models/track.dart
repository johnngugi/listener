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
    required this.number,
    required this.title,
    required this.length,
    required this.artist,
    required this.album,
    required this.releaseDate,
    required this.dateAdded,
    required this.plays,
    required this.cover,
    this.favorite = false,
    this.hasBadge = false,
  });

  final String number;
  final String title;
  final String length;
  final String artist;
  final String album;
  final String releaseDate;
  final String dateAdded;
  final String plays;
  final CoverStyle cover;
  final bool favorite;
  final bool hasBadge;
}

const tracks = [
  Track(
    number: '12',
    title: 'Congratulations',
    length: '4:54',
    artist: 'Ada Ehi',
    album: 'Born of God',
    releaseDate: '2020',
    dateAdded: '15 May 2026',
    plays: '0',
    cover: CoverStyle.sky,
  ),
  Track(
    number: '1',
    title:
        'I Don\'t Want to Miss a Thing (From "Armageddon" Soundtrack) (Album',
    length: '4:58',
    artist: 'Aerosmith',
    album: 'Armageddon - The Album',
    releaseDate: '1 Apr 1998',
    dateAdded: '15 May 2026',
    plays: '0',
    cover: CoverStyle.eclipse,
  ),
  Track(
    number: '1',
    title: 'Faded',
    length: '3:32',
    artist: 'Alan Walker',
    album: 'Faded',
    releaseDate: '4 Dec 2015',
    dateAdded: '15 May 2026',
    plays: '1',
    cover: CoverStyle.mist,
  ),
  Track(
    number: '2',
    title: 'Force',
    length: '4:00',
    artist: 'Alan Walker',
    album: 'Origins',
    releaseDate: '1 Jul 2022',
    dateAdded: '15 May 2026',
    plays: '0',
    cover: CoverStyle.monochrome,
  ),
  Track(
    number: '5',
    title: 'Fluorescent Adolescent',
    length: '2:53',
    artist: 'Arctic Monkeys',
    album: 'Favourite Worst Nightmare',
    releaseDate: '24 Apr 2007',
    dateAdded: '15 May 2026',
    plays: '0',
    cover: CoverStyle.street,
    hasBadge: true,
  ),
  Track(
    number: '12',
    title: '505',
    length: '4:13',
    artist: 'Arctic Monkeys',
    album: 'Favourite Worst Nightmare',
    releaseDate: '24 Apr 2007',
    dateAdded: '15 May 2026',
    plays: '0',
    cover: CoverStyle.street,
    hasBadge: true,
  ),
  Track(
    number: '1',
    title: 'Do I Wanna Know?',
    length: '4:32',
    artist: 'Arctic Monkeys',
    album: 'AM',
    releaseDate: '9 Sep 2013',
    dateAdded: '15 May 2026',
    plays: '0',
    cover: CoverStyle.wave,
    hasBadge: true,
  ),
  Track(
    number: '2',
    title: 'R U Mine?',
    length: '3:21',
    artist: 'Arctic Monkeys',
    album: 'AM',
    releaseDate: '9 Sep 2013',
    dateAdded: '15 May 2026',
    plays: '1',
    cover: CoverStyle.wave,
    hasBadge: true,
  ),
  Track(
    number: '3',
    title: 'One for the Road',
    length: '3:26',
    artist: 'Arctic Monkeys',
    album: 'AM',
    releaseDate: '9 Sep 2013',
    dateAdded: '15 May 2026',
    plays: '0',
    cover: CoverStyle.wave,
    hasBadge: true,
  ),
];
