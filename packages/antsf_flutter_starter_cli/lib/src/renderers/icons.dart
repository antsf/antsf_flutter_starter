import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Render flavor launcher resources in memory. Never writes into [project].
Map<String, List<int>> renderIcons(
  Map<String, dynamic> config,
  Directory project,
) {
  final flavors = config['flavors'] as Map;
  final files = <String, List<int>>{};
  final sources = <String, img.Image>{};
  img.Image load(String? source) => source == null
      ? _placeholder()
      : sources.putIfAbsent(source, () => _readSource(source, project));
  final base = load(config['icon'] as String?);
  for (final flavor in ['dev', 'stg', 'prod'].where(flavors.containsKey)) {
    final override = (flavors[flavor] as Map)['icon'] as String?;
    final art = override == null ? base : load(override);
    final image = flavor == 'prod' ? art : _badged(art, flavor);
    final encoded = <int, List<int>>{};
    List<int> png(int size) => encoded.putIfAbsent(
      size,
      () => img.encodePng(
        img.copyResize(
          image,
          width: size,
          height: size,
          interpolation: img.Interpolation.average,
        ),
      ),
    );
    for (final density in _densities.entries) {
      files['android/app/src/$flavor/res/mipmap-${density.key}/ic_launcher.png'] =
          png(density.value);
    }
    final directory = 'ios/Runner/Assets.xcassets/AppIcon-$flavor.appiconset';
    final images = <Map<String, String>>[];
    for (final slot in _iosSlots) {
      final filename = 'Icon-${slot.idiom}-${slot.size}@${slot.scale}x.png';
      files['$directory/$filename'] = png((slot.size * slot.scale).round());
      images.add({
        'size': '${_number(slot.size)}x${_number(slot.size)}',
        'idiom': slot.idiom,
        'filename': filename,
        'scale': '${slot.scale}x',
      });
    }
    files['$directory/Contents.json'] = utf8.encode(
      '${const JsonEncoder.withIndent('  ').convert({
        'images': images,
        'info': {'version': 1, 'author': 'xcode'},
      })}\n',
    );
  }
  return files;
}

img.Image _readSource(String source, Directory project) {
  final file = File(p.join(project.path, source));
  final decoded = img.decodeImage(file.readAsBytesSync());
  if (decoded == null) {
    throw FormatException('Cannot decode launcher icon: $source');
  }
  final square = img.copyResizeCropSquare(
    img.bakeOrientation(decoded),
    size: 1024,
    interpolation: img.Interpolation.linear,
  );
  // Flatten transparency onto white; iOS rejects alpha-channel launcher icons.
  final opaque = img.Image(width: 1024, height: 1024, numChannels: 3);
  img.fill(opaque, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(opaque, square);
  return opaque;
}

img.Image _badged(img.Image source, String flavor) {
  final output = img.Image.from(source);
  final color = flavor == 'dev'
      ? img.ColorRgb8(220, 65, 0)
      : img.ColorRgb8(105, 35, 170);
  // Draw with the package's built-in bitmap font. No OS fonts or binaries needed.
  final badge = img.Image(width: 256, height: 80, numChannels: 3);
  img.fill(badge, color: color);
  img.drawString(
    badge,
    flavor.toUpperCase(),
    font: img.arial48,
    color: img.ColorRgb8(255, 255, 255),
  );
  img.compositeImage(
    output,
    img.copyResize(
      badge,
      width: 1024,
      height: 320,
      interpolation: img.Interpolation.nearest,
    ),
    dstY: 704,
  );
  return output;
}

img.Image _placeholder() {
  final canvas = img.Image(width: 256, height: 256, numChannels: 3);
  img.fill(canvas, color: img.ColorRgb8(20, 80, 100));
  img.drawRect(
    canvas,
    x1: 20,
    y1: 20,
    x2: 235,
    y2: 235,
    color: img.ColorRgb8(255, 255, 255),
    thickness: 5,
  );
  img.drawString(
    canvas,
    'APP',
    font: img.arial48,
    y: 65,
    color: img.ColorRgb8(255, 255, 255),
  );
  img.drawString(
    canvas,
    'REPLACE ICON',
    font: img.arial24,
    y: 140,
    color: img.ColorRgb8(255, 255, 255),
  );
  return img.copyResize(
    canvas,
    width: 1024,
    height: 1024,
    interpolation: img.Interpolation.nearest,
  );
}

String _number(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

const _densities = {
  'mdpi': 48,
  'hdpi': 72,
  'xhdpi': 96,
  'xxhdpi': 144,
  'xxxhdpi': 192,
};

const _iosSlots = [
  _IconSlot('iphone', 20, 2),
  _IconSlot('iphone', 20, 3),
  _IconSlot('iphone', 29, 1),
  _IconSlot('iphone', 29, 2),
  _IconSlot('iphone', 29, 3),
  _IconSlot('iphone', 40, 2),
  _IconSlot('iphone', 40, 3),
  _IconSlot('iphone', 60, 2),
  _IconSlot('iphone', 60, 3),
  _IconSlot('ipad', 20, 1),
  _IconSlot('ipad', 20, 2),
  _IconSlot('ipad', 29, 1),
  _IconSlot('ipad', 29, 2),
  _IconSlot('ipad', 40, 1),
  _IconSlot('ipad', 40, 2),
  _IconSlot('ipad', 76, 1),
  _IconSlot('ipad', 76, 2),
  _IconSlot('ipad', 83.5, 2),
  _IconSlot('ios-marketing', 1024, 1),
];

class _IconSlot {
  const _IconSlot(this.idiom, this.size, this.scale);
  final String idiom;
  final double size;
  final int scale;
}
