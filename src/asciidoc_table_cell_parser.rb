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
    original_node_list = @converter.node_list.dup
    @converter.node_list = []

    if asciidoc_source_only?(cell)
      load_opts = build_load_options(@current_document)
      cell_doc = Asciidoctor.load(cell.text, **load_opts)
      cell_doc.blocks.each { |b| @converter.convert(b) }
    else
      cell.blocks.each { |b| @converter.convert(b) }
    end

    cell_content_nodes = @converter.node_list
    @converter.node_list = original_node_list

    if cell_content_nodes.empty? && !cell.text.to_s.empty?
      cell_content_nodes = [AdfBuilder.paragraph_node(@converter.send(:parse_or_escape, cell.text))]
    end

    cell_content_nodes
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
end
