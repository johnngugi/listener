import 'package:flutter/material.dart';
import 'package:listener_front/src/theme.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      color: panelColor,
      child: const Padding(
        padding: EdgeInsets.fromLTRB(26, 20, 24, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BrandHeader(),
            SizedBox(height: 22),
            SideSection(
              label: 'BROWSE',
              items: [
                SideItem(Icons.home_outlined, 'Home'),
                SideItem(Icons.library_music_outlined, 'Genres'),
              ],
            ),
            SizedBox(height: 36),
            SideSection(
              label: 'MY LIBRARY',
              items: [
                SideItem(Icons.album_outlined, 'Albums'),
                SideItem(Icons.hub_outlined, 'Artists'),
                SideItem(Icons.music_note_outlined, 'Tracks', selected: true),
                SideItem(Icons.folder_outlined, 'Folders'),
              ],
            ),
            Spacer(),
            PlaylistHeader(),
            SizedBox(height: 18),
            Text('Car Vocals', style: _sidebarItemStyle),
            SizedBox(height: 24),
            Text('Work', style: _sidebarItemStyle),
          ],
        ),
      ),
    );
  }
}

class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'Listener',
          style: TextStyle(
            color: textColor,
            fontSize: 36,
            height: 1,
            fontWeight: FontWeight.w300,
            letterSpacing: 0,
          ),
        ),
        const Spacer(),
        Icon(
          Icons.settings_outlined,
          size: 22,
          color: mutedColor.withValues(alpha: .9),
        ),
        const SizedBox(width: 20),
        Icon(
          Icons.more_horiz,
          size: 26,
          color: mutedColor.withValues(alpha: .9),
        ),
      ],
    );
  }
}

class SideSection extends StatelessWidget {
  const SideSection({super.key, required this.label, required this.items});

  final String label;
  final List<SideItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: textColor,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 14),
        for (final item in items) ...[item, const SizedBox(height: 20)],
      ],
    );
  }
}

class SideItem extends StatelessWidget {
  const SideItem(this.icon, this.title, {super.key, this.selected = false});

  final IconData icon;
  final String title;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? accentColor : mutedColor;

    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 14),
        Text(
          title,
          style: _sidebarItemStyle.copyWith(
            color: color,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class PlaylistHeader extends StatelessWidget {
  const PlaylistHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'PLAYLISTS',
          style: TextStyle(
            color: textColor,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        const Icon(Icons.chevron_right, color: mutedColor, size: 20),
        const Spacer(),
        Icon(Icons.add, color: mutedColor.withValues(alpha: .95), size: 22),
        const SizedBox(width: 20),
        Icon(
          Icons.more_horiz,
          color: mutedColor.withValues(alpha: .95),
          size: 25,
        ),
      ],
    );
  }
}

const _sidebarItemStyle = TextStyle(
  color: mutedColor,
  fontSize: 17,
  height: 1,
  letterSpacing: 0,
  fontWeight: FontWeight.w500,
);
