require 'minitest/autorun'
require 'asciidoctor'
require 'json'
require 'base64'
require 'fileutils'
require 'tmpdir'
require_relative '../src/adf_extensions'

class ImagesdirSwitchTest < Minitest::Test
  ONE_PX_PNG = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8Xw8AAoMBgQH0nKcAAAAASUVORK5CYII='
  TWO_PX_PNG = 'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAF0lEQVR42mP8/5+hHgMDAwMjIh8AAAwMAgH+VZSmAAAAAElFTkSuQmCC'

  def write_png(path, b64)
    File.open(path, 'wb') { |f| f.write(Base64.decode64(b64)) }
  end

  def test_imagesdir_switch_mid_document
    Dir.mktmpdir do |dir|
      img_dir1 = File.join(dir, 'imgset1')
      img_dir2 = File.join(dir, 'imgset2')
      FileUtils.mkdir_p img_dir1
      FileUtils.mkdir_p img_dir2

      img1_path = File.join(img_dir1, 'one.png')
      img2_path = File.join(img_dir2, 'two.png')
      write_png(img1_path, ONE_PX_PNG)
      write_png(img2_path, TWO_PX_PNG)

      adoc = <<~ADOC
      = ImageDir Switch Test
      :imagesdir: ./imgset1

      image::one.png[]

      :imagesdir: ./imgset2

      image::two.png[]
      ADOC

  doc = Asciidoctor.load(adoc, safe: :safe, backend: 'adf', base_dir: dir)
  output = doc.converter.convert(doc, 'document')
  refute_equal '', output, 'Conversion returned empty string – ADF converter not applied (converter class: ' + doc.converter.class.to_s + ')'
      json = JSON.parse(output)
      media_nodes = json['content'].select { |n| n['type'] == 'mediaSingle' }

      assert_equal 2, media_nodes.size, 'Should have two mediaSingle nodes'

      one = media_nodes.find { |n| n.dig('content',0,'attrs','id') == 'one.png' }
      two = media_nodes.find { |n| n.dig('content',0,'attrs','id') == 'two.png' }

      refute_nil one, 'First image (one.png) not found'
      refute_nil two, 'Second image (two.png) not found'

      w1 = one.dig('attrs','width')
      h1 = one.dig('content',0,'attrs','height')
      w2 = two.dig('attrs','width')
      h2 = two.dig('content',0,'attrs','height')

      # Ensure dimensions detected (1x1 and 2x2) demonstrating both directories resolved
      assert w1 && h1, 'Dimensions missing for first image'
      assert w2 && h2, 'Dimensions missing for second image'
      assert w1 <= 2 && h1 <= 2, 'Unexpected size for first image'
      assert w2 <= 4 && h2 <= 4, 'Unexpected size for second image'
    end
  end
end
