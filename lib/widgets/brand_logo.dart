import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/services/youtube_service.dart';
import '../data/labels.dart';
import '../ui/widgets/artwork.dart';

class BrandLogo extends StatefulWidget {
  const BrandLogo({super.key, required this.brand, this.size = 44});
  final MusicBrand brand;
  final double size;
  @override
  State<BrandLogo> createState() => _BrandLogoState();
}

class _BrandLogoState extends State<BrandLogo> {
  static final _cache = <String, String>{};
  late final Future<String> _url;
  @override
  void initState() {
    super.initState();
    _url = _load();
  }

  Future<String> _load() async {
    final brand = widget.brand;
    if (_cache.containsKey(brand.handle)) return _cache[brand.handle]!;
    try {
      final channels = context.read<YoutubeService>().client.channels;
      final channel =
          await (brand.channelId != null
                  ? channels.get(brand.channelId!)
                  : channels.getByHandle(brand.handle))
              .timeout(const Duration(seconds: 8));
      return _cache[brand.handle] = channel.logoUrl;
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _url,
    builder: (context, snap) {
      if (snap.data?.isNotEmpty == true)
        return Artwork(
          url: snap.data!,
          size: widget.size,
          radius: widget.size / 2,
        );
      return CircleAvatar(
        radius: widget.size / 2,
        child: Text(widget.brand.name.substring(0, 1)),
      );
    },
  );
}
