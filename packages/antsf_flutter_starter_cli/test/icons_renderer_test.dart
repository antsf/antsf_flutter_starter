import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:antsf_flutter_starter_cli/src/renderers/icons.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

import 'app_renderer_test.dart' show appConfig;

void main() {
  late Directory project;
  setUp(() => project = Directory.systemTemp.createTempSync('icon-renderer-'));
  tearDown(() => project.deleteSync(recursive: true));

  test('overrides preserve source art but DEV/STG receive opaque labeled color badges', () {
    void source(String path, int r, int g, int b) {
      final image = img.Image(width: 120, height: 80, numChannels: 4);
      img.fill(image, color: img.ColorRgba8(r, g, b, 255));
      File('${project.path}/$path').writeAsBytesSync(img.encodePng(image));
    }

    source('base.png', 8, 160, 40);
    source('stage.png', 15, 50, 190);
    final config = appConfig(staging: true);
    config['icon'] = 'base.png';
    config['flavors']['stg']['icon'] = 'stage.png';
    final files = renderIcons(config, project);
    img.Image icon(String name) => img.decodePng(
      Uint8List.fromList(
        files['ios/Runner/Assets.xcassets/AppIcon-$name.appiconset/Icon-ios-marketing-1024.0@1x.png']!,
      ),
    )!;
    final dev = icon('dev');
    final stg = icon('stg');
    final prod = icon('prod');
    expect(
      [dev.getPixel(5, 5).r, dev.getPixel(5, 5).g, dev.getPixel(5, 5).b],
      [8, 160, 40],
    );
    expect(
      [stg.getPixel(5, 5).r, stg.getPixel(5, 5).g, stg.getPixel(5, 5).b],
      [15, 50, 190],
    );
    expect(
      [
        prod.getPixel(5, 950).r,
        prod.getPixel(5, 950).g,
        prod.getPixel(5, 950).b,
      ],
      [8, 160, 40],
    );
    expect(
      [dev.getPixel(5, 950).r, dev.getPixel(5, 950).g, dev.getPixel(5, 950).b],
      [220, 65, 0],
    );
    expect(
      [stg.getPixel(5, 950).r, stg.getPixel(5, 950).g, stg.getPixel(5, 950).b],
      [105, 35, 170],
    );
    for (final image in [dev, stg]) {
      expect(
        image.where(
          (pixel) =>
              pixel.y >= 704 && pixel.r > 240 && pixel.g > 240 && pixel.b > 240,
        ),
        isNotEmpty,
        reason: 'Badge must include a readable built-in-font label',
      );
    }
    expect(
      project.listSync().length,
      2,
      reason: 'Only test source files exist',
    );
  });

  test('invalid or missing icon sources fail instead of silently using placeholders', () {
    final config = appConfig();
    config['icon'] = 'missing.png';
    expect(
      () => renderIcons(config, project),
      throwsA(isA<FileSystemException>()),
    );
    File('${project.path}/invalid.png').writeAsStringSync('not an image');
    config['icon'] = 'invalid.png';
    expect(() => renderIcons(config, project), throwsFormatException);
  });

  test('renders deterministic Android densities and complete iOS catalog per flavor', () {
    final config = appConfig(staging: true);
    final files = renderIcons(config, project);
    for (final flavor in ['dev', 'stg', 'prod']) {
      for (final density in {
        'mdpi': 48,
        'hdpi': 72,
        'xhdpi': 96,
        'xxhdpi': 144,
        'xxxhdpi': 192,
      }.entries) {
        final image = img.decodePng(
          Uint8List.fromList(
            files['android/app/src/$flavor/res/mipmap-${density.key}/ic_launcher.png']!,
          ),
        )!;
        expect(image.width, density.value);
        expect(image.height, density.value);
      }
      final directory = 'ios/Runner/Assets.xcassets/AppIcon-$flavor.appiconset';
      final contents =
          jsonDecode(utf8.decode(files['$directory/Contents.json']!)) as Map;
      final images = contents['images'] as List;
      expect(images, hasLength(19));
      for (final spec in images.cast<Map>()) {
        final pixels =
            (double.parse((spec['size'] as String).split('x').first) *
                    double.parse((spec['scale'] as String).replaceAll('x', '')))
                .round();
        final image = img.decodePng(
          Uint8List.fromList(files['$directory/${spec['filename']}']!),
        )!;
        expect(image.width, pixels);
        expect(image.height, pixels);
        expect(
          image.numChannels,
          3,
          reason: 'Apple icons must be opaque, no alpha channel',
        );
      }
      expect(images, contains(containsPair('idiom', 'ios-marketing')));
    }
    expect(renderIcons(config, project), equals(files));
    expect(
      project.listSync(),
      isEmpty,
      reason: 'Renderer must not write output',
    );
  });
}
