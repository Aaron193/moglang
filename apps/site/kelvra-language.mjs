import fs from 'node:fs';

const kelvraGrammar = JSON.parse(
	fs.readFileSync(
		new URL('../../tooling/vscode-kelvra/syntaxes/kelvra.tmLanguage.json', import.meta.url),
		'utf8',
	),
);

export const kelvraShikiOptions = {
	langs: [kelvraGrammar],
	langAlias: { kelvra: kelvraGrammar.name },
};
