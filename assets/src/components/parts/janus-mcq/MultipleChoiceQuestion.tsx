/* eslint-disable react/prop-types */
import { usePrevious } from 'components/hooks/usePrevious';
import { shuffle } from 'lodash';
import React, { CSSProperties, useCallback, useEffect, useState } from 'react';
import { parseBool } from 'utils/common';
import { CapiVariableTypes } from '../../../adaptivity/capi';
import { renderFlow } from '../janus-text-flow/TextFlow';
import { CapiVariable } from '../types/parts';
import {
  JanusMultipleChoiceQuestionItemProperties,
  JanusMultipleChoiceQuestionProperties,
} from './MultipleChoiceQuestionType';

// SS assumes the unstyled "text" of the label is the text value
// there should only be one node in a label text, but we'll concat them jic
const getNodeText = (node: any): any => {
  if (Array.isArray(node)) {
    return node.reduce((txt, newNode) => (txt += getNodeText(newNode)), '');
  }
  let nodeText = node.text || '';
  nodeText += node.children.reduce((childrenText: any, childNode: any) => {
    let txt = childrenText;
    txt += getNodeText(childNode);
    return txt;
  }, '');
  return nodeText;
};

const MCQItemContent: React.FC<any> = ({ nodes, state }) => {
  return (
    <div>
      {nodes.map((subtree: any) => {
        const style: any = {};
        if (subtree.tag === 'p') {
          // PMP-347
          const hasImages = subtree.children.some((child: { tag: string }) => child.tag === 'img');
          if (hasImages) {
            style.display = 'inline-block';
          }
        }
        return renderFlow('root', subtree, style, state);
      })}
    </div>
  );
};
const MCQItem: React.FC<JanusMultipleChoiceQuestionProperties> = ({
  nodes,
  state,
  multipleSelection,
  itemId,
  layoutType,
  totalItems,
  groupId,
  selected = false,
  onSelected,
  val,
  disabled,
}) => {
  const mcqItemStyles: CSSProperties = {};
  if (layoutType === 'horizontalLayout') {
    const hasImages = nodes.some((node: any) =>
      node.children.some((child: { tag: string }) => child.tag === 'img'),
    );
    const hasBlankSpans = nodes.some((node: any) =>
      node.children.some(
        (child: { tag: string; children: string | any[] }) =>
          child.tag === 'span' && child.children.length === 0,
      ),
    );
    if (hasImages || hasBlankSpans) {
      mcqItemStyles.width = `calc(${100 / totalItems}% - 6px)`;
    }
    mcqItemStyles.display = `inline-block`;
  }

  const textValue = getNodeText(nodes);

  const handleChanged = (e: { target: { checked: any } }) => {
    const selection = {
      value: val,
      textValue,
      checked: e.target.checked,
    };
    onSelected(selection);
  };

  return (
    <div style={mcqItemStyles}>
      <input
        name={groupId}
        id={itemId}
        type={multipleSelection ? 'checkbox' : 'radio'}
        value={val}
        disabled={disabled}
        className="input_30cc60b8-382a-470c-8cd9-908348c58ebe"
        checked={selected}
        onChange={handleChanged}
      />
      <label htmlFor={itemId}>
        <MCQItemContent nodes={nodes} state={state} />
      </label>
    </div>
  );
};
const MultipleChoiceQuestion: React.FC<JanusMultipleChoiceQuestionItemProperties> = (props) => {
  const [state, setState] = useState<any[]>(Array.isArray(props.state) ? props.state : []);
  const [model, setModel] = useState<any>(Array.isArray(props.model) ? props.model : {});
  const [ready, setReady] = useState<boolean>(false);
  const id: string = props.id;

  const [enabled, setEnabled] = useState(true);
  const [randomized, setRandomized] = useState(false);
  const [options, setOptions] = useState<any[]>([]);
  const [numberOfSelectedChoices, setNumberOfSelectedChoices] = useState(0);
  // note in SS selection is 1 based
  const [selectedChoice, setSelectedChoice] = useState<number>(0);
  const [selectedChoiceText, setSelectedChoiceText] = useState<string>('');
  const [selectedChoices, setSelectedChoices] = useState<any[]>([]);
  const [selectedChoicesText, setSelectedChoicesText] = useState<any[]>([]);
  const prevSelectedChoice = usePrevious<number>(selectedChoice);
  const prevSelectedChoices = usePrevious<any[]>(selectedChoices);

  const initialize = useCallback(async (pModel) => {
    // set defaults from model
    const dEnabled = typeof pModel.enabled === 'boolean' ? pModel.enabled : enabled;
    setEnabled(dEnabled);

    const dRandomized = typeof pModel.randomized === 'boolean' ? pModel.randomized : randomized;
    setRandomized(dRandomized);

    // BS: not sure I grok this one
    const dMcqItems = pModel.mcqItems || [];
    setSelectedChoicesText(
      dMcqItems.map((item: { nodes: any }, index: number) => {
        return {
          value: index + 1,
          textValue: getNodeText(item.nodes),
          checked: false,
        };
      }),
    );

    // now we need to save the defaults used in adaptivity (not necessarily the same)
    const initResult = await props.onInit({
      id,
      responses: [
        {
          key: 'enabled',
          type: CapiVariableTypes.BOOLEAN,
          value: dEnabled,
        },
        {
          key: 'randomize',
          type: CapiVariableTypes.BOOLEAN,
          value: dRandomized,
        },
        {
          key: 'numberOfSelectedChoices',
          type: CapiVariableTypes.NUMBER,
          value: numberOfSelectedChoices,
        },
        {
          key: 'selectedChoice',
          type: CapiVariableTypes.NUMBER,
          value: selectedChoice,
        },
        {
          key: 'selectedChoiceText',
          type: CapiVariableTypes.STRING,
          value: selectedChoiceText,
        },
        {
          key: 'selectedChoices',
          type: CapiVariableTypes.ARRAY,
          value: selectedChoices,
        },
        {
          key: 'selectedChoicesText',
          type: CapiVariableTypes.ARRAY,
          value: selectedChoicesText,
        },
      ],
    });

    // result of init has a state snapshot with latest (init state applied)
    const currentStateSnapshot = initResult.snapshot;
    setState(currentStateSnapshot);
    const sEnabled = currentStateSnapshot[`stage.${id}.enabled`];
    if (sEnabled !== undefined) {
      setEnabled(sEnabled);
    }

    setReady(true);
  }, []);

  const {
    x = 0,
    y = 0,
    z = 0,
    width,
    multipleSelection,
    mcqItems,
    customCssClass,
    layoutType,
  } = model;

  useEffect(() => {
    let pModel;
    let pState;
    if (typeof props?.model === 'string') {
      try {
        pModel = JSON.parse(props.model);
        setModel(pModel);
      } catch (err) {
        // bad json, what do?
      }
    }
    if (typeof props?.state === 'string') {
      try {
        pState = JSON.parse(props.state);
        setState(pState);
      } catch (err) {
        // bad json, what do?
      }
    }
    if (!pModel) {
      return;
    }
    initialize(pModel);
  }, [props]);

  useEffect(() => {
    if (!ready) {
      return;
    }
    props.onReady({ id, responses: [] });
  }, [ready]);

  // Set up the styles
  const styles: CSSProperties = {
    position: 'absolute',
    top: y,
    left: x,
    width,
    zIndex: z,
  };

  if (layoutType === 'verticalLayout') {
    const hasImages = mcqItems.some((item: any) =>
      item.nodes.some((node: any) =>
        node.children.some((child: { tag: string }) => child.tag === 'img'),
      ),
    );
  }

  const handleStateChange = (stateData: CapiVariable[]) => {
    // this runs every time state is updated from *any* source
    // the global variable state
    const interested = stateData.filter((stateVar) => stateVar.id.indexOf(`stage.${id}.`) === 0);
    if (interested?.length) {
      interested.forEach((stateVar) => {
        switch (stateVar.key) {
          case 'enabled':
            // will check for boolean and string truthiness for enabled
            setEnabled(parseBool(stateVar.value));
            break;
          case 'randomize':
            // will check for boolean and string truthiness for randomize
            setRandomized(parseBool(stateVar.value));
            break;
          case 'numberOfSelectedChoices':
            {
              const num = parseInt(stateVar.value as string, 10);
              if (numberOfSelectedChoices !== num) {
                setNumberOfSelectedChoices(num);
              }
            }
            break;
          case 'selectedChoice':
            {
              const choice = parseInt(stateVar.value as string, 10);
              if (selectedChoice !== choice) {
                setSelectedChoice(choice);
              }
            }
            break;
          case 'selectedChoiceText':
            setSelectedChoiceText(stateVar.value.toString());
            break;
          case 'selectedChoices':
            if (Array.isArray(stateVar.value)) {
              // converts string values to numbers
              const updatedValues = stateVar.value.map((item) =>
                !Number.isNaN(parseFloat(item)) ? parseFloat(item) : item,
              );
              setSelectedChoices(updatedValues);
            }
            break;
          case 'selectedChoicesText':
            {
              const vals = stateVar.value;
              if (Array.isArray(vals)) {
                // compare selectedChoicesText with array of strings from state
                // then update 'checked' value based on strings
                const choices = selectedChoicesText.map((choice) => ({
                  ...choice,
                  checked: vals.includes(choice.textValue),
                }));
                setSelectedChoicesText(choices);
              }
            }
            break;
        }
      });
    }
  };

  useEffect(() => {
    // we need to set up a new list so that we can shuffle while maintaining correct index/values
    let mcqList: any[] = mcqItems?.map((item: any, index: number) => ({
      ...item,
      index: index,
      value: index + 1,
    }));

    if (randomized) {
      mcqList = shuffle(mcqList);
    }

    setOptions(mcqList);
  }, [mcqItems]);

  useEffect(() => {
    // watch for a new choice then
    // trigger item selection handler
    if (selectedChoice !== prevSelectedChoice && selectedChoice !== 0) {
      handleItemSelection({
        value: selectedChoice,
        textValue: selectedChoiceText,
        checked: true,
      });
    }
  }, [selectedChoice]);

  useEffect(() => {
    // watch for new choices that may be set programmatically
    // trigger item selection handler for each
    if (
      multipleSelection &&
      prevSelectedChoices &&
      // if previous selected is less than 1 and selected are greater than 1
      ((prevSelectedChoices.length < 1 && selectedChoices.length > 0) ||
        // if previous selected contains values and the values don't match currently selected values
        (prevSelectedChoices.length > 0 &&
          !prevSelectedChoices.every((fact) => selectedChoices.includes(fact))))
    ) {
      selectedChoicesText.forEach((option) => {
        handleItemSelection({
          value: option.value,
          textValue: option.textValue,
          checked: selectedChoices.includes(option.value),
        });
      });
    }
  }, [selectedChoices]);

  const handleItemSelection = ({
    value,
    textValue,
    checked,
  }: {
    value: number;
    textValue: string;
    checked: boolean;
  }) => {
    // TODO: non-number values?? - pb: I suspect not, since there's no SS ability to specify a value for an item
    const newChoice = parseInt(value.toString(), 10);
    let newCount = 1;

    let newSelectedChoices = [newChoice];
    let updatedChoicesText = [textValue];

    if (!multipleSelection) {
      // sets data for radios, which can only have single values
      setNumberOfSelectedChoices(newCount);
      setSelectedChoice(checked ? newChoice : 0);
      setSelectedChoiceText(checked ? textValue : '');
    } else {
      // sets data for checkboxes, which can have multiple values
      newSelectedChoices = [...new Set([...selectedChoices, newChoice])].filter(
        (c) => checked || (!checked && newChoice !== c),
      );

      const updatedSelections = selectedChoicesText.map((item) => {
        const modifiedItem = { ...item };
        modifiedItem.checked = item.value === value ? checked : item.checked;
        return modifiedItem;
      });

      updatedChoicesText = updatedSelections
        .filter((item) => item.checked)
        .map((item) => item.textValue);

      newCount = newSelectedChoices.length;
      setNumberOfSelectedChoices(newCount);
      setSelectedChoices(newSelectedChoices);
      setSelectedChoicesText(updatedSelections);
    }
    saveState({
      numberOfSelectedChoices: newCount,
      selectedChoice:
        multipleSelection && newSelectedChoices?.length
          ? newSelectedChoices[newSelectedChoices.length - 1]
          : checked
          ? newChoice
          : 0,
      selectedChoiceText:
        multipleSelection && updatedChoicesText?.length
          ? updatedChoicesText[updatedChoicesText.length - 1]
          : checked
          ? textValue
          : '',
      selectedChoices: newSelectedChoices,
      selectedChoicesText: updatedChoicesText,
    });
  };

  const saveState = ({
    numberOfSelectedChoices,
    selectedChoice,
    selectedChoiceText,
    selectedChoices,
    selectedChoicesText,
  }: {
    numberOfSelectedChoices: number;
    selectedChoice: number;
    selectedChoiceText: string;
    selectedChoices: number[];
    selectedChoicesText: string[];
  }) => {
    props.onSave({
      id: `${id}`,
      responses: [
        {
          key: 'numberOfSelectedChoices',
          type: CapiVariableTypes.NUMBER,
          value: numberOfSelectedChoices,
        },
        {
          key: 'selectedChoice',
          type: CapiVariableTypes.NUMBER,
          value: selectedChoice,
        },
        {
          key: 'selectedChoiceText',
          type: CapiVariableTypes.STRING,
          value: selectedChoiceText,
        },
        {
          key: 'selectedChoices',
          type: CapiVariableTypes.ARRAY,
          value: selectedChoices,
        },
        {
          key: 'selectedChoicesText',
          type: CapiVariableTypes.ARRAY,
          value: selectedChoicesText,
        },
      ],
    });
  };

  const isItemSelected = (index: number) => {
    // checks if the item is selected to set the input's "selected" attr
    let selected = false;
    if (multipleSelection) {
      selected = selectedChoices.includes(index + 1);
    } else {
      selected = selectedChoice === index + 1;
    }
    return selected;
  };

  return ready ? (
    <div
      data-janus-type={props.type}
      id={id}
      style={styles}
      className={`mcq-input ${customCssClass}`}
    >
      {options?.map((item, index) => (
        <MCQItem
          key={`${id}-item-${index}`}
          totalItems={options.length}
          layoutType={layoutType}
          itemId={`${id}-item-${index}`}
          groupId={`mcq-${id}`}
          selected={isItemSelected(item.index)}
          val={item.value}
          onSelected={handleItemSelection}
          state={state}
          {...item}
          x={0}
          y={0}
          disabled={!enabled}
          multipleSelection={multipleSelection}
        />
      ))}
    </div>
  ) : null;
};

export const tagName = 'janus-mcq';

export default MultipleChoiceQuestion;