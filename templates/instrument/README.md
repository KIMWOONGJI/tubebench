# Templates for a new instrument driver

Starting files for `docs/adding_an_instrument.md` (read that guide first; the contract is
`docs/instrument_interface.md`). This folder is **not** on the MATLAB path and not a package
folder, so nothing here is registered or run by accident; `tests/TestInstrumentTemplates` copies
the files into a temporary `+tim/+instr` folder and checks that the three driver templates pass
`tests/TestInstrumentContract` and their own tests as they are.

| File | What it is | Copy to |
|---|---|---|
| `TemplateSource.m` | signal-source driver of a request / response instrument (SCPI over TCP, VISA, serial) | `+tim/+instr/<Name>.m` |
| `TemplateAcquisition.m` | acquisition driver of a device whose data arrive while it records (streaming, background read) | `+tim/+instr/<Name>.m` |
| `TemplateCombined.m` | driver of one device with an output and four inputs on one clock, recorded in blocks (DAQ card, audio interface) | `+tim/+instr/<Name>.m` |
| `MockTemplateSource.m`, `MockTemplateAcquisition.m`, `MockTemplateCombined.m` | the protocol mock of each driver template: the instrument in software, coupled to the virtual tube | `+tim/+instr/Mock<Name>.m` |
| `TestTemplateSource.m`, `TestTemplateAcquisition.m`, `TestTemplateCombined.m` | the driver test of each driver template | `tests/Test<Name>.m` |
| `ref_template.md` | protocol reference with a manual source for every command | `docs/ref_<instrument>.md` |
| `config_snippet.json` | configuration sections that select the drivers (a source and a separate DAQ) | into a copy of a `formatVersion` 2 configuration |

The guide's step 3 copies the three files of one template and replaces, case-sensitive, the class
name (`TemplateSource` → `<Name>`; this also renames `MockTemplateSource` and
`TestTemplateSource`), the same in capitals in the help lines (`TEMPLATESOURCE`) and the registry
name (`templatesource` → `<registry name>`). Then work through every line marked `TODO`: each one
is an instrument fact that comes from the programming manual. The worked example is the demo
source (`+tim/+instr/DemoSource.m`, `MockDemoSource.m`, `tests/TestDemoSource.m`,
`docs/ref_demo_source.md`), made from `TemplateSource` by following the guide.
