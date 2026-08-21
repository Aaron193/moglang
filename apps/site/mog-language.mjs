import fs from 'node:fs';

const mogGrammar = JSON.parse(
	fs.readFileSync(
		new URL('../../tooling/vscode-mog/syntaxes/mog.tmLanguage.json', import.meta.url),
		'utf8',
	),
);

export const mogShikiOptions = {
	langs: [mogGrammar],
	langAlias: { mog: mogGrammar.name },
};
