#!/usr/bin/env ruby
# frozen_string_literal: true

require 'asciidoctor'
require_relative 'adf_builder'

# Parses an AsciiDoc table cell whose style is :asciidoc into ADF nodes.
# This logic was previously embedded inline inside AdfConverter; extracting keeps
# AdfConverter leaner and makes the behaviour unit-testable in isolation.
class AsciidocTableCellParser
  def initialize(converter:, current_document: nil)
    @converter = converter
    @current_document = current_document
  end

  # Returns an array of ADF block nodes. Falls back to a single paragraph if parsing yields nothing.
  def parse(cell)
    if asciidoc_source_only?(cell)
      text = cell.text.to_s
      # If the text is multi-line or clearly contains list markers, use a nested doc
      # to allow full AsciiDoc parsing (lists, multiple paragraphs, etc.).
      if text.include?("\n") || text.match?(/(^|\n)\s*(?:[*\-]\s|\d+\.\s)/)
        load_opts = build_load_options(@current_document)
        cell_doc = Asciidoctor.load(text, **load_opts)
        adf_json = cell_doc.convert
        nodes = []
        begin
          adf = adf_json ? JSON.parse(adf_json) : nil
          nodes = (adf.is_a?(Hash) && adf['content'].is_a?(Array)) ? adf['content'] : []
        rescue JSON::ParserError
          nodes = []
        end
        # Fallback: if nested conversion yielded nothing, convert via outer paragraph to get inline macros
        return nodes unless nodes.empty?
        return convert_text_via_outer_paragraph(text, cell)
      else
        # Simple inline content (links, mentions, etc.): use outer converter paragraph
        return convert_text_via_outer_paragraph(text, cell)
      end
    else
      # For cells with parsed blocks or default style, use the outer converter for blocks
      original_node_list = @converter.node_list.dup
      @converter.node_list = []
      cell.blocks.each { |b| @converter.convert(b) }
      cell_content_nodes = @converter.node_list
      @converter.node_list = original_node_list
      # If there are no blocks but we have text (default cells), build a paragraph using parse_or_escape
      if cell_content_nodes.empty? && !cell.text.to_s.empty?
        inlines = @converter.send(:parse_or_escape, cell.text)
        cell_content_nodes = [AdfBuilder.paragraph_node(inlines)]
      end
      # Expand any inline placeholders now using the same converter registry
      cell_content_nodes = @converter.send(:expand_placeholders_in_nodes, cell_content_nodes)
      # Ensure at least an empty paragraph when no content was produced
      cell_content_nodes = [AdfBuilder.paragraph_node([])] if cell_content_nodes.nil? || cell_content_nodes.empty?
      cell_content_nodes
    end
  end

  private

  def asciidoc_source_only?(cell)
    (cell.blocks.nil? || cell.blocks.empty?) && !cell.text.to_s.empty?
  end

  def build_load_options(doc)
    return { safe: :safe, backend: 'adf' } unless doc
    {
      safe: (doc.safe || :safe),
      backend: 'adf',
      attributes: doc.attributes.dup,
      base_dir: doc.base_dir
    }.compact
  end

  def convert_text_via_outer_paragraph(text, cell)
    original_node_list = @converter.node_list.dup
    @converter.node_list = []
    # Build a paragraph block in the context of the current document so that
    # registered inline macros (e.g., links, atlasMention) are applied.
    para = Asciidoctor::Block.new(@current_document || cell.document, :paragraph, source: text)
    @converter.convert(para)
    nodes = @converter.node_list
    @converter.node_list = original_node_list
    nodes = @converter.send(:expand_placeholders_in_nodes, nodes)
    nodes = [AdfBuilder.paragraph_node([])] if nodes.nil? || nodes.empty?
    nodes
  end
end
