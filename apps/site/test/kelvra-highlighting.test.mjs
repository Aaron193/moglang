import assert from 'node:assert/strict';
import test from 'node:test';
import {
	ExpressiveCodeEngine,
	loadShikiTheme,
	pluginShiki,
} from 'expressive-code';
import { kelvraShikiOptions } from '../kelvra-language.mjs';

function textContent(node) {
	if (node.type === 'text') return node.value;
	return node.children?.map(textContent).join('') ?? '';
}

function styledTokens(node, tokens = []) {
	if (typeof node.properties?.style === 'string') {
		tokens.push({ text: textContent(node), style: node.properties.style });
	}
	for (const child of node.children ?? []) styledTokens(child, tokens);
	return tokens;
}

test('the shared Kelvra grammar highlights kelvra code blocks', async () => {
	const engine = new ExpressiveCodeEngine({
		themes: [await loadShikiTheme('github-dark')],
		plugins: [pluginShiki(kelvraShikiOptions)],
	});
	const result = await engine.render({
		code: 'fn greet(name str) str { return name; }',
		language: 'kelvra',
	});
	const tokens = styledTokens(result.renderedGroupAst);

	for (const expected of ['fn', 'greet', 'name', 'str', 'return']) {
		assert.ok(tokens.some(({ text }) => text === expected), `missing styled ${expected} token`);
	}
	assert.ok(new Set(tokens.map(({ style }) => style)).size > 1);
});
