extension FamilyInfo {
    static let texts: [VerbFamily: Texts] = [
        .are: Texts(
            formation: [
                .init(label: "Stamm:", text: "-are fällt weg: parlare → parl-. Daran tritt die Endung für Zeit und Person – in den Beispielen unten hervorgehoben."),
                .init(label: "Passato prossimo:", text: "avere oder essere im Presente + Partizip auf -ato: ho parlato, sono arrivato."),
            ],
            caveats: [
                .init(label: "Futuro und Condizionale:", text: "Das a der Endung wird zu e: parlerò, parlerei – nicht parlarò."),
                .init(label: "Congiuntivo:", text: "-are-Verben bekommen i-Endungen: che io parli. Bei -ere und -ire ist es umgekehrt (che io creda)."),
                .init(label: "Imperativo:", text: "tu endet auf -a: parla! – im Presente dagegen tu parli."),
            ]
        ),
        .ere: Texts(
            formation: [
                .init(label: "Stamm:", text: "-ere fällt weg: credere → cred-. Daran tritt die Endung für Zeit und Person – in den Beispielen unten hervorgehoben."),
                .init(label: "Passato prossimo:", text: "avere oder essere im Presente + Partizip auf -uto: ho creduto. Gerade bei -ere haben aber viele Verben ein eigenes Partizip."),
            ],
            caveats: [
                .init(label: "Partizip nach c:", text: "Ein i hält das c weich: conoscere → conosciuto, piacere → piaciuto."),
                .init(label: "Aussprache:", text: "c und g klingen vor o und a hart, vor e und i weich: conosco („sk“), aber conosci („sch“); leggo („g“), aber leggi („dsch“). Geschrieben wird beides gleich."),
                .init(label: "Congiuntivo:", text: "a-Endungen: che io creda. Bei -are ist es umgekehrt (che io parli)."),
                .init(label: "Imperativo:", text: "tu wie im Presente: credi!"),
            ]
        ),
        .ire: Texts(
            formation: [
                .init(label: "Stamm:", text: "-ire fällt weg: dormire → dorm-. Daran tritt die Endung für Zeit und Person – in den Beispielen unten hervorgehoben."),
                .init(label: "Passato prossimo:", text: "avere oder essere im Presente + Partizip auf -ito: ho dormito, sono partito."),
            ],
            caveats: [
                .init(label: "Fast wie -ere:", text: "Im Presente weicht nur voi ab: dormite (aber credete). Imperfetto, Futuro und Condizionale behalten das i: dormivo, dormirò, dormirei."),
                .init(label: "Mit oder ohne -isc-:", text: "Der Infinitiv verrät nicht, ob ein -ire-Verb -isc- einschiebt: dormire → dormo, aber capire → capisco. Die Verben mit -isc- bilden eine eigene Gruppe."),
                .init(label: "Congiuntivo:", text: "a-Endungen wie bei -ere: che io dorma."),
                .init(label: "Imperativo:", text: "tu wie im Presente: dormi!"),
            ]
        ),
        .isc: Texts(
            formation: [
                .init(label: "Stamm:", text: "-ire fällt weg: capire → cap-. Daran tritt die Endung für Zeit und Person – in den Beispielen unten hervorgehoben."),
                .init(label: "-isc-:", text: "Im Presente kommt bei io, tu, lui/lei und loro -isc- zwischen Stamm und Endung: capisco, capisci, capisce, capiscono. Bei noi und voi nicht: capiamo, capite."),
                .init(label: "Passato prossimo:", text: "avere oder essere im Presente + Partizip auf -ito: ho capito."),
            ],
            caveats: [
                .init(label: "Congiuntivo und Imperativo:", text: "Auch hier -isc-, wieder außer bei noi und voi: che io capisca, che loro capiscano; capisci!, capisca!"),
                .init(label: "Ohne -isc-:", text: "Imperfetto, Futuro, Condizionale und Partizip: capivo, capirò, capirei, capito."),
                .init(label: "Aussprache:", text: "sc klingt vor o und a wie „sk“ (capisco, capisca), vor e und i wie „sch“ (capisci, capisce)."),
                .init(label: "Welche Verben?", text: "Der Infinitiv verrät nicht, ob ein -ire-Verb -isc- einschiebt: capire → capisco, aber dormire → dormo."),
            ]
        ),
    ]
}
