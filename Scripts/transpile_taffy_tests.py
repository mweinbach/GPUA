#!/usr/bin/env python3
"""
transpile_taffy_tests.py — Deterministic transpiler for Taffy 0.9.0 Chrome layout conformance fixtures.

Translates the 116 selected representative Rust test fixtures from `.upstream/taffy/tests/generated/`
into native Swift Testing suites in `Tests/TaffyTests/Generated/`.
All expected coordinate numbers and assertions are preserved verbatim with 0.1px tolerance.
"""

import os
import re

STYLE_PARAM_ORDER = {p: i for i, p in enumerate([
    'display', 'itemIsTable', 'itemIsReplaced', 'boxSizing', 'overflow',
    'scrollbarWidth', 'position', 'inset', 'size', 'minSize', 'maxSize',
    'aspectRatio', 'margin', 'padding', 'border', 'alignItems', 'alignSelf',
    'justifyItems', 'justifySelf', 'alignContent', 'justifyContent', 'gap',
    'textAlign', 'flexDirection', 'flexWrap', 'flexBasis', 'flexGrow', 'flexShrink',
    'gridTemplateRows', 'gridTemplateColumns', 'gridAutoRows', 'gridAutoColumns',
    'gridAutoFlow', 'gridTemplateAreas', 'gridTemplateColumnNames', 'gridTemplateRowNames',
    'gridRow', 'gridColumn'
])}

RECT_PARAM_ORDER = {p: i for i, p in enumerate(['left', 'right', 'top', 'bottom'])}
SIZE_PARAM_ORDER = {p: i for i, p in enumerate(['width', 'height'])}
LINE_PARAM_ORDER = {p: i for i, p in enumerate(['start', 'end'])}

def clean_numbers(s):
    def repl_f(m):
        val = m.group(1)
        if '.' not in val:
            val += '.0'
        return val
    s = re.sub(r'([0-9]+(?:\.[0-9]+)?)f(?:32|64)', repl_f, s)
    s = re.sub(r'([0-9]+)u(?:8|16|32|64|size)', r'\1', s)
    s = re.sub(r'(-?[0-9]+)i(?:8|16|32|64|size)', r'\1', s)
    return s

def split_top_level_args(s):
    args = []
    current = []
    depth = 0
    for ch in s:
        if ch in '([{':
            depth += 1
            current.append(ch)
        elif ch in ')]}':
            depth -= 1
            current.append(ch)
        elif ch == ',' and depth == 0:
            arg = ''.join(current).strip()
            if arg:
                args.append(arg)
            current = []
        else:
            current.append(ch)
    arg = ''.join(current).strip()
    if arg:
        args.append(arg)
    return args

def sort_struct_args(text, struct_name, order_dict):
    pattern = re.compile(r'\b' + struct_name + r'\s*\(')
    tag = f'___{struct_name.upper()}___'
    while True:
        m = pattern.search(text)
        if not m:
            break
        depth = 0
        start_idx = m.end() - 1
        end_idx = -1
        for i in range(start_idx, len(text)):
            if text[i] == '(':
                depth += 1
            elif text[i] == ')':
                depth -= 1
                if depth == 0:
                    end_idx = i
                    break
        if end_idx == -1:
            break
        inner = text[start_idx+1:end_idx].strip()
        if inner:
            args = split_top_level_args(inner)
            sorted_args = sorted(args, key=lambda a: order_dict.get(a.split(':')[0].strip(), 999))
            replacement = f'{tag}(' + ', '.join(sorted_args) + ')'
        else:
            replacement = f'{tag}()'
        text = text[:m.start()] + replacement + text[end_idx+1:]
    return text.replace(tag, struct_name)

def convert_struct_braces(text, struct_name):
    pattern = re.compile(r'\b' + struct_name + r'\s*\{')
    while True:
        m = pattern.search(text)
        if not m:
            break
        start_idx = m.end() - 1
        depth = 0
        end_idx = -1
        for i in range(start_idx, len(text)):
            if text[i] == '{':
                depth += 1
            elif text[i] == '}':
                depth -= 1
                if depth == 0:
                    end_idx = i
                    break
        if end_idx == -1:
            break
        inner = text[start_idx+1:end_idx]
        text = text[:m.start()] + struct_name + '(' + inner + ')' + text[end_idx+1:]
    return text

def transpile_body(body):
    # Remove rust prints and unused attributes
    body = re.sub(r'println!\([^\)]*\);', '', body)
    body = re.sub(r'taffy\.print_tree\([^\)]*\);', '', body)
    body = re.sub(r'#\[allow\([^\)]*\)\]', '', body)
    body = re.sub(r'use taffy::[^\n]*;', '', body)
    body = re.sub(r'use RepetitionCount::[^\n]*;', '', body)
    body = re.sub(r'let\s+mut\s+', 'var ', body)
    
    # Clean numeric suffixes
    body = clean_numbers(body)
    
    # Remove Rust Some(...) wrapper
    body = re.sub(r'\bSome\(([^)]+)\)', r'\1', body)
    
    # Replace crate::
    body = body.replace('crate::new_test_tree()', 'newTestTree()')
    body = body.replace('crate::test_measure_function', 'testMeasureFunction')
    body = body.replace('crate::TestNodeContext::ahem_text', 'TestNodeContext.ahemText')
    body = body.replace('crate::WritingMode::Horizontal', '.horizontal')
    body = body.replace('crate::WritingMode::Vertical', '.vertical')
    
    # Replace taffy namespaces
    body = body.replace('taffy::style::', '')
    body = body.replace('taffy::geometry::', '')
    body = body.replace('taffy::prelude::', '')
    body = body.replace('taffy::', '')
    
    # Replace enums
    body = body.replace('Display::Grid', 'Display.grid')
    body = body.replace('Display::Flex', 'Display.flex')
    body = body.replace('Display::Block', 'Display.block')
    body = body.replace('Display::None', 'Display.none')
    body = body.replace('BoxSizing::ContentBox', '.contentBox')
    body = body.replace('BoxSizing::BorderBox', '.borderBox')
    body = body.replace('Position::Absolute', '.absolute')
    body = body.replace('Position::Relative', '.relative')
    body = body.replace('Overflow::Scroll', '.scroll')
    body = body.replace('Overflow::Visible', '.visible')
    body = body.replace('Overflow::Hidden', '.hidden')
    body = body.replace('Overflow::Clip', '.clip')
    body = body.replace('FlexDirection::ColumnReverse', '.columnReverse')
    body = body.replace('FlexDirection::RowReverse', '.rowReverse')
    body = body.replace('FlexDirection::Column', '.column')
    body = body.replace('FlexDirection::Row', '.row')
    body = body.replace('FlexWrap::WrapReverse', '.wrapReverse')
    body = body.replace('FlexWrap::Wrap', '.wrap')
    body = body.replace('FlexWrap::NoWrap', '.noWrap')
    
    # AlignItems
    body = body.replace('AlignItems::Start', '.start')
    body = body.replace('AlignItems::End', '.end')
    body = body.replace('AlignItems::FlexEnd', '.flexEnd')
    body = body.replace('AlignItems::FlexStart', '.flexStart')
    body = body.replace('AlignItems::Center', '.center')
    body = body.replace('AlignItems::Stretch', '.stretch')
    body = body.replace('AlignItems::Baseline', '.baseline')

    # AlignSelf
    body = body.replace('AlignSelf::Start', '.start')
    body = body.replace('AlignSelf::End', '.end')
    body = body.replace('AlignSelf::FlexEnd', '.flexEnd')
    body = body.replace('AlignSelf::FlexStart', '.flexStart')
    body = body.replace('AlignSelf::Center', '.center')
    body = body.replace('AlignSelf::Stretch', '.stretch')
    body = body.replace('AlignSelf::Baseline', '.baseline')

    # JustifyItems
    body = body.replace('JustifyItems::Start', '.start')
    body = body.replace('JustifyItems::End', '.end')
    body = body.replace('JustifyItems::FlexEnd', '.flexEnd')
    body = body.replace('JustifyItems::FlexStart', '.flexStart')
    body = body.replace('JustifyItems::Center', '.center')
    body = body.replace('JustifyItems::Stretch', '.stretch')
    body = body.replace('JustifyItems::Baseline', '.baseline')

    # AlignContent
    body = body.replace('AlignContent::Start', '.start')
    body = body.replace('AlignContent::End', '.end')
    body = body.replace('AlignContent::FlexEnd', '.flexEnd')
    body = body.replace('AlignContent::FlexStart', '.flexStart')
    body = body.replace('AlignContent::Center', '.center')
    body = body.replace('AlignContent::SpaceBetween', '.spaceBetween')
    body = body.replace('AlignContent::SpaceAround', '.spaceAround')
    body = body.replace('AlignContent::SpaceEvenly', '.spaceEvenly')
    body = body.replace('AlignContent::Stretch', '.stretch')

    # JustifyContent
    body = body.replace('JustifyContent::Start', '.start')
    body = body.replace('JustifyContent::End', '.end')
    body = body.replace('JustifyContent::FlexEnd', '.flexEnd')
    body = body.replace('JustifyContent::FlexStart', '.flexStart')
    body = body.replace('JustifyContent::Center', '.center')
    body = body.replace('JustifyContent::SpaceBetween', '.spaceBetween')
    body = body.replace('JustifyContent::SpaceAround', '.spaceAround')
    body = body.replace('JustifyContent::SpaceEvenly', '.spaceEvenly')
    body = body.replace('JustifyContent::Stretch', '.stretch')

    # Grid Placement
    body = body.replace('GridPlacement::Auto', '.auto')
    body = re.sub(r'GridPlacement::Span\(([^)]+)\)', r'span(\1)', body)
    body = re.sub(r'GridPlacement::Line\(([^)]+)\)', r'line(\1)', body)

    body = body.replace('GridAutoFlow::RowDense', '.rowDense')
    body = body.replace('GridAutoFlow::ColumnDense', '.columnDense')
    body = body.replace('GridAutoFlow::Row', '.row')
    body = body.replace('GridAutoFlow::Column', '.column')
    
    # AutoFill / AutoFit / repeat
    body = body.replace('RepetitionCount::AutoFill', '.autoFill')
    body = body.replace('RepetitionCount::AutoFit', '.autoFit')
    body = body.replace('AutoFill', '.autoFill')
    body = body.replace('AutoFit', '.autoFit')
    body = re.sub(r'\brepeat\(', 'repeat_(', body)

    # Dimensions & Sizes
    body = re.sub(r'Dimension::from_length\(([^)]+)\)', r'.fromLength(\1)', body)
    body = re.sub(r'Dimension::from_percent\(([^)]+)\)', r'.fromPercent(\1)', body)
    body = body.replace('Dimension::AUTO', '.auto()')
    body = body.replace('Dimension::Auto', '.auto()')
    body = body.replace('LengthPercentageAuto::AUTO', '.auto()')
    body = body.replace('LengthPercentageAuto::Auto', '.auto()')
    body = body.replace('LengthPercentage::Auto', '.auto()')
    body = body.replace('LengthPercentage::ZERO', '.zero()')
    body = body.replace('Size::MAX_CONTENT', 'Size.MAX_CONTENT')
    body = body.replace('Size::MIN_CONTENT', 'Size.MIN_CONTENT')
    body = body.replace('Size::ZERO', 'Size.ZERO')
    
    # Vec & arrays
    while 'vec!' in body:
        new_body = re.sub(r'vec!\[([^\]]*)\]', r'[\1]', body)
        if new_body == body:
            break
        body = new_body
    body = re.sub(r'&\[([^\]]*)\]', r'[\1]', body)
    
    # Style field names snake_case -> camelCase
    field_maps = [
        ('flex_direction:', 'flexDirection:'),
        ('flex_wrap:', 'flexWrap:'),
        ('flex_basis:', 'flexBasis:'),
        ('flex_grow:', 'flexGrow:'),
        ('flex_shrink:', 'flexShrink:'),
        ('align_items:', 'alignItems:'),
        ('align_self:', 'alignSelf:'),
        ('justify_items:', 'justifyItems:'),
        ('justify_self:', 'justifySelf:'),
        ('align_content:', 'alignContent:'),
        ('justify_content:', 'justifyContent:'),
        ('aspect_ratio:', 'aspectRatio:'),
        ('min_size:', 'minSize:'),
        ('max_size:', 'maxSize:'),
        ('box_sizing:', 'boxSizing:'),
        ('grid_template_rows:', 'gridTemplateRows:'),
        ('grid_template_columns:', 'gridTemplateColumns:'),
        ('grid_auto_rows:', 'gridAutoRows:'),
        ('grid_auto_columns:', 'gridAutoColumns:'),
        ('grid_auto_flow:', 'gridAutoFlow:'),
        ('grid_row:', 'gridRow:'),
        ('grid_column:', 'gridColumn:'),
        ('scrollbar_width:', 'scrollbarWidth:'),
    ]
    for k, v in field_maps:
        body = body.replace(k, v)
        
    # Remove ..Default::default()
    body = re.sub(r',?\s*\.\.Default::default\(\)', '', body)
    body = re.sub(r'\s*\.\.Default::default\(\)', '', body)

    # Convert struct braces Foo { ... } -> Foo( ... )
    for st in ['Rect', 'Size', 'Point', 'Line', 'Style']:
        body = convert_struct_braces(body, st)

    # Sort arguments to match Swift parameter declaration order
    body = sort_struct_args(body, 'Style', STYLE_PARAM_ORDER)
    body = sort_struct_args(body, 'Rect', RECT_PARAM_ORDER)
    body = sort_struct_args(body, 'Size', SIZE_PARAM_ORDER)
    body = sort_struct_args(body, 'Line', LINE_PARAM_ORDER)

    # Convert new_leaf / new_leaf_with_context / new_with_children
    body = re.sub(r'taffy\s*\.\s*new_leaf_with_context', 'try! taffy.newLeafWithContext', body)
    body = re.sub(r'taffy\s*\.\s*new_leaf', 'try! taffy.newLeaf', body)
    body = re.sub(r'taffy\s*\.\s*new_with_children', 'try! taffy.newWithChildren', body)
    
    # taffy.compute_layout_with_measure(...)
    body = re.sub(r'taffy\s*\.\s*compute_layout_with_measure\(([^,]+),\s*([^,]+),\s*([^\)]+)\)\.unwrap\(\);?',
                  r'_ = try! taffy.computeLayoutWithMeasure(\1, \2, \3).get();', body)

    lines = body.split('\n')
    out_lines = []
    current_node = None
    for line in lines:
        m_layout = re.search(r'let\s+layout\s*=\s*taffy\.layout\(([^)]+)\)\.unwrap\(\);?', line)
        if m_layout:
            current_node = m_layout.group(1).strip()
            out_lines.append(f'        let layout_{current_node} = try! taffy.layout({current_node}).get()')
            continue
        if 'let Layout { size, location' in line:
            continue
        
        m_assert_w = re.search(r'assert_eq!\(size\.width,\s*([^,]+),', line)
        if m_assert_w:
            exp = m_assert_w.group(1).strip()
            out_lines.append(f'        #expect(abs(layout_{current_node}.size.width - ({exp})) < 0.1)')
            continue

        m_assert_h = re.search(r'assert_eq!\(size\.height,\s*([^,]+),', line)
        if m_assert_h:
            exp = m_assert_h.group(1).strip()
            out_lines.append(f'        #expect(abs(layout_{current_node}.size.height - ({exp})) < 0.1)')
            continue

        m_assert_x = re.search(r'assert_eq!\(location\.x,\s*([^,]+),', line)
        if m_assert_x:
            exp = m_assert_x.group(1).strip()
            out_lines.append(f'        #expect(abs(layout_{current_node}.location.x - ({exp})) < 0.1)')
            continue

        m_assert_y = re.search(r'assert_eq!\(location\.y,\s*([^,]+),', line)
        if m_assert_y:
            exp = m_assert_y.group(1).strip()
            out_lines.append(f'        #expect(abs(layout_{current_node}.location.y - ({exp})) < 0.1)')
            continue

        m_scroll_w = re.search(r'assert_eq!\(\s*layout\.scroll_width\(\),\s*([^,]+),', line)
        if m_scroll_w:
            exp = m_scroll_w.group(1).strip()
            out_lines.append(f'        #expect(abs(layout_{current_node}.scrollWidth() - ({exp})) < 0.1)')
            continue

        m_scroll_h = re.search(r'assert_eq!\(\s*layout\.scroll_height\(\),\s*([^,]+),', line)
        if m_scroll_h:
            exp = m_scroll_h.group(1).strip()
            out_lines.append(f'        #expect(abs(layout_{current_node}.scrollHeight() - ({exp})) < 0.1)')
            continue

        if '#[cfg(' in line or '#[test]' in line or '#[allow(' in line:
            continue
            
        out_lines.append(line)
        
    result = '\n'.join(out_lines)
    # Finally, replace any remaining .unwrap() with .get()
    result = result.replace('.unwrap()', '.get()')
    return result

def transpile_fixture(category, filename):
    p = os.path.join('.upstream/taffy/tests/generated', category, filename)
    with open(p) as f:
        content = f.read()
    tests = re.findall(r'fn\s+([a-zA-Z0-9_]+)\s*\(\)\s*\{([\s\S]*?)\n\}', content)
    output = []
    for name, body in tests:
        swift_body = transpile_body(body)
        test_case = f"""    @Test("{name}")
    func test_{name}() {{
{swift_body}
    }}
"""
        output.append(test_case)
    return output

FLEX_FIXTURES = [
    'flex_grow_to_min.rs', 'flex_grow_less_than_factor_one.rs', 'flex_grow_flex_basis_percent_min_max.rs',
    'flex_grow_within_constrained_max_row.rs', 'flex_grow_within_constrained_max_column.rs',
    'flex_grow_shrink_at_most.rs', 'flex_grow_child.rs', 'flex_grow_0_min_size.rs',
    'flex_shrink_to_zero.rs', 'flex_shrink_by_outer_margin_with_max_size.rs', 'flex_shrink_flex_grow_row.rs',
    'flex_shrink_flex_grow_child_flex_shrink_other_child.rs', 'flex_basis_flex_shrink_row.rs',
    'flex_basis_flex_shrink_column.rs', 'flex_basis_unconstraint_row.rs',
    'flex_basis_and_main_dimen_set_when_flexing.rs', 'flex_basis_smaller_then_content_with_flex_grow_large_size.rs',
    'flex_basis_smaller_then_content_with_flex_grow_small_size.rs', 'flex_basis_flex_grow_row.rs',
    'flex_basis_flex_grow_column.rs', 'wrap_reverse_row.rs', 'wrap_reverse_column.rs',
    'wrap_row.rs', 'wrap_column.rs', 'flex_wrap_wrap_to_child_height.rs',
    'flex_wrap_children_with_min_main_overriding_flex_basis.rs', 'align_items_center.rs',
    'align_items_flex_end.rs', 'align_items_stretch.rs', 'align_baseline_child.rs',
    'align_self_center.rs', 'align_self_flex_end_override_flex_start.rs',
    'align_content_center_wrapped.rs', 'align_content_space_between_wrapped.rs',
    'justify_content_row_center.rs', 'justify_content_row_flex_end.rs',
    'justify_content_row_space_between.rs', 'justify_content_row_space_around.rs',
    'justify_content_row_space_evenly.rs', 'justify_content_overflow_min_max.rs',
    'gap_row_gap_determines_parent_height.rs', 'gap_column_gap_determines_parent_width.rs',
    'align_content_center_wrapped_negative_space_gap.rs',
    'gap_column_gap_percentage_cyclic_partially_shrinkable.rs', 'margin_auto_left.rs',
    'margin_auto_right.rs', 'margin_auto_left_and_right.rs',
    'margin_auto_bottom_and_top_justify_center.rs', 'absolute_child_with_main_margin.rs',
    'absolute_child_with_cross_margin.rs',
    'absolute_layout_align_items_and_justify_content_center.rs',
    'absolute_layout_in_wrap_reverse_column_container.rs', 'absolute_aspect_ratio_fill_width.rs',
    'absolute_aspect_ratio_fill_height.rs', 'aspect_ratio_flex_row_fill_width.rs',
    'aspect_ratio_flex_column_fill_height.rs',
]

GRID_FIXTURES = [
    'grid_fr_fixed_size_no_content_proportions.rs', 'grid_fr_fixed_size_single_item.rs',
    'grid_fr_span_2_proportion.rs', 'grid_fr_fixed_size_no_content_proportions_sub_1_sum.rs',
    'grid_auto_takes_precedence_over_fr.rs', 'grid_fr_span_2_proportion_with_non_spanned_track.rs',
    'grid_minmax_auto_fixed_10px.rs', 'grid_minmax_auto_max_content.rs',
    'grid_minmax_auto_min_content.rs', 'grid_minmax_auto_percent_definite.rs',
    'grid_minmax_column_fixed_width_above_range.rs', 'grid_fit_content_percent_definite_argument.rs',
    'grid_placement_auto_negative.rs', 'grid_placement_definite_primary.rs',
    'grid_span_2_max_content_auto_indefinite.rs', 'grid_auto_fill_fixed_size.rs',
    'grid_auto_fit_definite_percentage.rs', 'grid_auto_columns_fixed_width.rs',
    'grid_align_content_center.rs', 'grid_align_content_end.rs',
    'grid_justify_content_center.rs', 'grid_justify_content_end.rs',
    'grid_align_items_baseline.rs', 'grid_justify_items_sized_center.rs',
    'grid_absolute_align_self_sized_all.rs', 'grid_absolute_column_start.rs',
    'grid_absolute_column_end.rs', 'grid_aspect_ratio_absolute_fill_width_from_inset.rs',
    'grid_aspect_ratio_absolute_fill_height_from_inset.rs', 'grid_absolute_container_bottom_left.rs',
]

BLOCK_FIXTURES = [
    'block_margin_auto_left.rs', 'block_margin_auto_right.rs',
    'block_margin_auto_left_and_right.rs', 'block_margin_auto_bottom_and_top.rs',
    'block_margin_auto_left_and_right_with_auto_width.rs', 'block_margin_auto_multiple_children.rs',
    'block_margin_y_collapse_complex.rs', 'block_margin_y_collapse_through_blocked_by_border_top.rs',
    'block_margin_y_collapse_through_blocked_by_border_bottom.rs',
    'block_margin_y_collapse_through_blocked_by_padding_top.rs',
    'block_margin_y_collapse_through_blocked_by_padding_bottom.rs',
    'block_margin_y_collapse_through_blocked_by_height.rs', 'block_border_fixed_size.rs',
    'block_border_percentage_fixed_size.rs', 'block_absolute_layout_percentage_height.rs',
    'block_absolute_layout_percentage_bottom_based_on_parent_height.rs',
    'block_absolute_child_with_margin_x.rs', 'block_absolute_child_with_margin_y.rs',
    'block_absolute_layout_within_border.rs',
    'block_absolute_margin_auto_left_and_right_with_inset.rs',
]

HYBRID_FIXTURES = [
    ('blockflex', 'blockflex_block_in_flex_column.rs'),
    ('blockflex', 'blockflex_block_in_flex_row.rs'),
    ('blockflex', 'blockflex_flex_in_block.rs'),
    ('blockgrid', 'blockgrid_grid_in_block.rs'),
    ('blockgrid', 'blockgrid_block_in_grid_auto.rs'),
    ('blockgrid', 'blockgrid_margin_y_collapse_through_blocked_by_grid.rs'),
    ('gridflex', 'gridflex_row_integration.rs'),
    ('gridflex', 'gridflex_column_integration.rs'),
    ('leaf', 'leaf_with_content_and_padding_border.rs'),
    ('leaf', 'leaf_with_content_and_padding.rs'),
]

def generate_suite(suite_name, suite_desc, fixtures_list, output_path):
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    tests = []
    for item in fixtures_list:
        if isinstance(item, tuple):
            cat, fn = item
        else:
            cat = suite_name.lower()
            fn = item
        tests.extend(transpile_fixture(cat, fn))
    
    header = f"""// Swift-only: Chrome conformance layout test suite for Taffy ({suite_desc}) transpiled from upstream tests/generated/
import Testing
@testable import Taffy

@Suite("Taffy Conformance: {suite_desc}")
struct {suite_name}ConformanceTests {{
"""
    footer = "}\n"
    content = header + '\n'.join(tests) + footer
    with open(output_path, 'w') as f:
        f.write(content)
    print(f"Generated {output_path} with {len(tests)} tests.")

if __name__ == '__main__':
    generate_suite('Flex', 'Flexbox', FLEX_FIXTURES, 'Tests/TaffyTests/Generated/FlexConformanceTests.swift')
    generate_suite('Grid', 'CSS Grid', GRID_FIXTURES, 'Tests/TaffyTests/Generated/GridConformanceTests.swift')
    generate_suite('Block', 'CSS Block', BLOCK_FIXTURES, 'Tests/TaffyTests/Generated/BlockConformanceTests.swift')
    generate_suite('Hybrid', 'Hybrid & Leaf', HYBRID_FIXTURES, 'Tests/TaffyTests/Generated/HybridConformanceTests.swift')
